/*
Table dominoes

The two hardest things to create are the internal representation and the GUI
display, so let's start there.
*/
GTK2.Window mainwindow;

int main()
{
	GTK2.setup_gtk();
	mainwindow=GTK2.Window(GTK2.WINDOW_TOPLEVEL);
	mainwindow->add(GTK2.Label("This is a stub! There's no code yet."))->show_all()->signal_connect("destroy",lambda() {exit(0);});
	return -1;
}
