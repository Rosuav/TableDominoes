/*
Table dominoes

Original game by Sid Sackson, under the name "Domino Bead Game". Further
modifications by Marjo and Chris Angelico.

The two hardest things to create are the internal representation and the GUI
display, so let's start there.

Dominoes are placed in a grid. This grid is of theoretically-infinite size,
but since there are only thirty dominoes in play, it's impossible to extend
further out than (-60,-60)-(60,60). Therefore the board is laid out on that
mythical grid. (The limit is a compiler constant.) The UI (GTK2.Table) works
with nonnegative integers only, so it uses the limit as an offset. (It's not
majorly bothered by having a whole lot of empty slots in it, so the display
shouldn't be too huge.)

The internal representation is a 2D array, with the same offset. (So, in
effect, the grid is (0,0)-(120,120), and activity starts at (60,60)-(61,61).)
Each cell is an integer with the number of pips, or'd with a flag from the
enumeration. If the cell is empty, it is the integer 0; having zero pips is
distinguishable because all the OTHER_* flags are nonzero. The significance
of the different OTHER_* flags is twofold: firstly, the display should show
a different line between them (indicating that it's a single domino across
the two cells), and secondly, no more than three consecutive cells may have
the same OTHER_ type - that is, four horizontally all showing OTHER_ABOVE is
illegal, as is four vertically showing OTHER_RIGHT.

A valid move consists of either vertical or horizontal placement of a domino.
It must be across two empty cells, must not violate the aforementioned OTHER_
consecutive count, and must be adjacent to other dominoes such that two lines
are extended. (TODO: Clarify that in code terms.) Also, each sequence extended
must be valid, per the rules of sequences: as soon as a number is repeated, it
MUST loop the sequence. So, for instance, "3 4 1" may be followed by 3, which
would close the sequence and require a following 4, or by 0 or 2, which will
leave the sequence unclosed. ("3 4 1 0 2" has no numbers left, so the next
domino must close the sequence with a 3.)

Scoring can wait for version two.

Tiles in hands, or in the boneyard, are represented by integers, eg the 2 4 is
represented as 0x24. The offset (4 bits) is configurable, in case you want to
run a larger set of dominoes.
*/

/*
There's some sort of weird bug that I'm having trouble tracking down. The
immediate symptom is that the display goes wonky - some dominoes seem to be
drawn improperly aligned. I don't know whether it's a display-only issue or
an error of representation.
*/
GTK2.Window mainwindow;
GTK2.Table table;

enum {EMPTY=0, OTHER_ABOVE=0x1000, OTHER_BELOW=0x2000, OTHER_LEFT=0x3000, OTHER_RIGHT=0x4000, OTHER_MASK=0x7000};

constant max_pip=4,domino_sets=2; //Play with two 4 4 domino sets
//In a 4 4 set of dominoes, there are (4+1)*(4+2)/2 dominoes (15).
//We have multiple sets, and each tile has two pips. However, it's
//not actually possible, per the rules, to stting them out quite
//like that, so the final multiplication by 2 isn't done. But for
//a generic domino game engine, double this value.
constant offset=(max_pip+1)*(max_pip+2)/2*domino_sets;
array(array(int)) board=allocate(offset*2,allocate(offset*2));

constant tile_shift=4,tile_mask=(1<<tile_shift)-1;
array(int) boneyard;

void makeboneyard()
{
	boneyard=allocate(offset);
	int i=0;
	for (int s=0;s<domino_sets;++s)
		for (int x=0;x<=max_pip;++x)
			for (int y=0;y<=x;++y)
				boneyard[i++]=x<<tile_shift|y;
	if (i!=offset) exit(1,"ASSERT FAIL: Got %d tiles, expected %d!\n",i,offset);
	//write("%{%02X %}\n",boneyard);
}

GTK2.Widget pip(int|string n)
{
	return GTK2.Label((string)n)->set_size_request(30,30);
}

//TODO: Dedup these two
void place_horiz(int row,int col,int tile)
{
	board[row][col]=(tile>>tile_shift) | OTHER_RIGHT;
	board[row][col+1]=(tile&tile_mask) | OTHER_LEFT;
	table->attach(
		GTK2.Frame()->add(GTK2.Hbox(0,0)
			->add(pip(tile>>tile_shift))
			->add(GTK2.Vseparator())
			->add(pip(tile&tile_mask))
		)->set_shadow_type(GTK2.SHADOW_ETCHED_OUT)->show_all()
	,col,col+2,row,row+1,GTK2.Fill|GTK2.Expand,GTK2.Fill|GTK2.Expand,2,2);
}

void place_vert(int row,int col,int tile)
{
	board[row][col]=(tile>>tile_shift) | OTHER_BELOW;
	board[row+1][col]=(tile&tile_mask) | OTHER_ABOVE;
	table->attach(
		GTK2.Frame()->add(GTK2.Vbox(0,0)
			->add(pip(tile>>tile_shift))
			->add(GTK2.Hseparator())
			->add(pip(tile&tile_mask))
		)->set_shadow_type(GTK2.SHADOW_ETCHED_OUT)->show_all()
	,col,col+1,row,row+2,GTK2.Fill|GTK2.Expand,GTK2.Fill|GTK2.Expand,2,2);
}

//Figure out if a tile is a double (eg 2 2). Uses weird modulo arithmetic. :)
int is_double(int tile)
{
	return !(tile%(1<<tile_shift|1));
}

//Flip a tile end for end. With doubles, flip(x)==x.
int flip(int tile)
{
	return (tile&tile_mask)<<tile_shift | tile>>tile_shift;
}

//Find valid horizontal moves involving anything from the current hand
array low_list_valid_moves(array(int) hand,array(array(int)) board,int otherflag)
{
	array moves=({});
	foreach (board;int r;array(int) row) for (int c=0;c<sizeof(row)-2;++c)
	{
		if (row[c] || row[c+1]) continue; //Can't put anything here, it's occupied.
		//This is pretty brute-force. I need to find the intersection
		//between legal moves and the player's hand. This could be done
		//either by figuring out what's legal and then looking through
		//the hand, or by iterating through the hand and seeing if each
		//is legal. Since, in a multiplayer game, the hand is likely to
		//be relatively small (14 in a two-player game, less with more
		//players - and shrinking), I'm iterating through the hand.
		//Once again, lots of duplication. Please refactor if possble.

		//See if there are already three parallel tiles.
		//Note that if there are two on one side of us and one on the other,
		//all parallel to the one we're about to place, that's a violation,
		//same as if there were three already there. The half-and-half
		//situation is pretty unlikely, but coping with that is why the count
		//is simply maintained.
		int parallel=0;
		for (int rr=r-1;rr>=0 && (board[rr][c]&OTHER_MASK)==otherflag;--rr) ++parallel;
		for (int rr=r+1;rr<sizeof(board) && (board[rr][c]&OTHER_MASK)==otherflag;++rr) ++parallel;
		if (parallel>2) continue; //No placing anything there.
		//Anything adjacent to us? If not, don't do any of the checks.
		int above=r<sizeof(board)-1 && (board[r+1][c] || board[r+1][c+1]);
		int below=r>0 && (board[r-1][c] || board[r-1][c+1]);
		int left=c>0 && board[r][c-1]; //Cannons to the left of us?
		int right=c<sizeof(row)-2 && board[r][c+2]; //Cannons to the right of us?
		if (above || below || left || right)
		{
			//There's something. Let's try this.
			multiset(int) tried=(<>);
			//Somewhat hackish: Try each tile potentially twice, flipping in
			//between. After flipping twice, it's certain to be in tried[],
			//so we won't infinitely loop. Plus, doubles (which are the same
			//once flipped) don't need to be tried twice, and duplicate tiles
			//can also be skipped. It covers all cases.
			foreach (hand;int i;int tile) while (1)
			{
				if (tried[tile]) break;
				int legal=1;
				board[r][c]=tile>>tile_shift; board[r][c+1]=tile&tile_mask;
				array(int) lines=({ });
				if (above || below)
				{
					for (int cc=c;cc<=c+1;++cc)
					{
						int r1=r-1; while (r1>=0 && board[r1][cc]) --r1;
						int r2=r+1; while (r1<sizeof(board) && board[r2][cc]) ++r2;
						++r1; --r2;
						if (r1==r && r2==r) continue;
						//At this point, the vertical strip from (r1,cc) to (r2,cc)
						//is a consecutive chain of tiles. Usually either r1 or r2
						//will be equal to r (both is possible but only because we
						//have two iterations on cc - a domino could stick out), but
						//it's entirely possible that they'll both be different, in
						//which case we're actually merging two lines. This will be
						//VERY rare in actual gameplay, but possible; and legal only
						//if the entire new line follows a single pattern.
						//Mask it off so we just get the tile value, not the OTHER_.
						int ok=1;
						array(int) pattern=({board[r1][cc]&tile_mask});
						for (int rr=r1+1;rr<=r2;++rr)
						{
							int cur=board[rr][cc]&tile_mask;
							if (cur==pattern[0]) {pattern=pattern[1..]+({cur}); ok=2;} //Looped pattern.
							else if (ok==1 && !has_value(pattern,cur)) pattern+=({cur}); //Pattern hasn't looped yet
							else {ok=0; break;} //Broken pattern.
						}
						if (!ok) {legal=0; break;} //Not a legal move - breaks a pattern.
						lines+=({r2-r1+1});
						if (r1<r && r2>r) lines+=({lines[-1]}); //If you linked two, count it twice! CJA rule, may not be quite official.
					}
				}
				if (legal && (left || right))
				{
					//And hello duplication... only this time, we don't need to check twice.
					//The cc in the loop above is just c here. Well, actually it's r here, but same diff.
					int c1=c-1; while (c1>=0 && board[r][c1]) --c1;
					int c2=c+2; while (c1<sizeof(row) && board[r][c2]) ++c2;
					++c1; --c2;
					//As above, the horizontal strip from (r,c1) to (r,c2)
					//is a consecutive chain of tiles. One or both must differ
					//from c or c+1; if they were both equal to those, then the
					//check (left || right) would have been false.
					int ok=1;
					array(int) pattern=({board[r][c1]&tile_mask});
					for (int cc=c1+1;cc<=c2;++cc)
					{
						int cur=board[r][cc]&tile_mask;
						if (cur==pattern[0]) {pattern=pattern[1..]+({cur}); ok=2;} //Looped pattern.
						else if (ok==1 && !has_value(pattern,cur)) pattern+=({cur}); //Pattern hasn't looped yet
						else {ok=0; break;} //Broken pattern.
					}
					if (!ok) {legal=0; break;} //Not a legal move - breaks a pattern.
					lines+=({c2-c1+1});
				}
				if (legal && sizeof(lines)>1) moves+=({({tile,r,c,'H'})});
				tried[tile]=1;
				tile=flip(tile);
			}
			board[r][c]=board[r][c+1]=0;
		}
	}
	return moves;
}

//Find valid moves involving anything from the current hand
array list_valid_moves(array(int) hand)
{
	array ret=low_list_valid_moves(hand,board,OTHER_RIGHT); //Easy part.
	//Now flip the board and get vertical moves.
	array vert=low_list_valid_moves(hand,Array.transpose(board),OTHER_BELOW);
	//And flip the moves back.
	foreach (vert,array move) ret+=({({move[0],move[2],move[1],'V'})});
	return ret;
}

int nomoves;
void make_move(string name,array(int) hand)
{
	if (nomoves) return;
	array moves;
	write("%O seconds to list ",gauge {moves=list_valid_moves(hand);});
	write("%d valid moves with %d pieces.\n",sizeof(moves),sizeof(hand));
	if (sizeof(moves))
	{
		[int tile,int r,int c,int type]=random(moves);
		write("%s: Placing %02X at (%d,%d) %sly.\n",name,tile,r,c,(['H':"horizontal",'V':"vertical"])[type]);
		if (type=='V') place_vert(r,c,tile);
		else place_horiz(r,c,tile);
		int i=search(hand,tile); if (i==-1) i=search(hand,flip(tile));
		hand=hand[..i-1]+hand[i+1..];
	}
	if (sizeof(hand)) call_out(make_move,4,name,hand);
	/*for (int r=0;r<sizeof(board);r+=2) for (int c=0;c<sizeof(board[0]);++c)
	{
		if (!c) write("\n");
		write("%c",":.' "[!board[r][c] + 2*!board[r+1][c]]);
	}
	write("\n");*/
}

int main()
{
	makeboneyard();
	GTK2.setup_gtk();
	mainwindow=GTK2.Window(GTK2.WINDOW_TOPLEVEL);
	table=GTK2.Table(sizeof(board),sizeof(board[0]),0);
	for (int i=20;i<41;++i) table
		->attach_defaults(pip(""),i,i+1,0,1)
		->attach_defaults(pip(""),0,1,i,i+1)
	;
	mainwindow->set_title("Table Dominoes")->add(GTK2.Vbox(0,10)
		//->add(GTK2.Label("Hello, world!"))
		->add(table)
		/*->add(GTK2.HbuttonBox()
			->add(GTK2.Button("Make a move"))
		)*/
	)->show_all()->signal_connect("destroy",lambda() {exit(0);});
	//Take two random tiles from the boneyard, avoiding any doubles,
	//and place them at (offset, offset{,+1}) and (offset+1, offset{,+1}).
	//Note that the original rules merely specify that having two
	//identical doubles results in a redeal, but the game's more fun if
	//there are no doubles to start with. (Redeals are cheap with a
	//computer, but more costly with physical tiles.)
	while (1)
	{
		int t=random(sizeof(boneyard));
		if (is_double(boneyard[t])) continue;
		int tile=boneyard[t];
		if (random(2)) tile=flip(tile);
		boneyard=boneyard[..t-1]+boneyard[t+1..]; //Remove it
		if (board[offset][offset])
		{
			//Second tile.
			place_horiz(offset+1,offset,tile);
			break; //Done!
		}
		//First tile.
		place_horiz(offset,offset,tile);
		//And continue to the second tile.
	}
	array hand=({ });
	for (int i=0;i<offset/2-1;++i) //2 = number of players
	{
		int t=random(sizeof(boneyard));
		hand+=({boneyard[t]});
		boneyard=boneyard[..t-1]+boneyard[t+1..];
	}
	signal(2,lambda() {nomoves=1; signal(2,exit);});
	call_out(make_move,2,"Player 1",hand);
	call_out(make_move,4,"Player 2",boneyard);
	return -1;
}
