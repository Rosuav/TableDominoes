/*
Table dominoes

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
GTK2.Window mainwindow;
GTK2.Table table;

enum {EMPTY=0, OTHER_ABOVE=0x1000, OTHER_BELOW=0x2000, OTHER_LEFT=0x3000, OTHER_RIGHT=0x4000};

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
	write("%{%02X %}\n",boneyard);
}

GTK2.Widget pip(int n)
{
	return GTK2.Label((string)n)->set_size_request(30,30);
}

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

int main()
{
	makeboneyard();
	GTK2.setup_gtk();
	mainwindow=GTK2.Window(GTK2.WINDOW_TOPLEVEL);
	table=GTK2.Table(sizeof(board),sizeof(board[0]),0);
	mainwindow->set_title("Table Dominoes")->add(GTK2.Vbox(0,10)
		->add(GTK2.Label("Hello, world!"))
		->add(table)
		->add(GTK2.HbuttonBox()
			->add(GTK2.Button("Make a move"))
		)
	)->show_all()->signal_connect("destroy",lambda() {exit(0);});
	//Take two random tiles from the boneyard, avoiding any doubles,
	//and place them at (offset, offset{,+1}) and (offset+1, offset{,+1}).
	while (1)
	{
		int t=random(sizeof(boneyard));
		if (!(boneyard[t]%(1<<tile_shift|1))) continue; //Skip doubles
		int tile=boneyard[t];
		if (random(2)) tile=(tile&tile_mask)<<tile_shift | tile>>tile_shift; //Flip the tile
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
	return -1;
}
