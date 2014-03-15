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
*/
GTK2.Window mainwindow;

enum {EMPTY=0, OTHER_ABOVE=0x1000, OTHER_BELOW=0x2000, OTHER_LEFT=0x3000, OTHER_RIGHT=0x4000};

int main()
{
	GTK2.setup_gtk();
	mainwindow=GTK2.Window(GTK2.WINDOW_TOPLEVEL);
	mainwindow->add(GTK2.Label("This is a stub! There's no code yet."))->show_all()->signal_connect("destroy",lambda() {exit(0);});
	return -1;
}
