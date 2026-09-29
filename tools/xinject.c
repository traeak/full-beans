#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

/* Send a ButtonPress/ButtonRelease to a window via XSendEvent.

   This X server drops XTEST-synthesised button events (so `xdotool click` is a
   no-op), but XSendEvent to the target window is delivered. Motion via XTEST
   does work, which is why hover could be tested with xdotool but clicks cannot.

   Build:  gcc -o /tmp/xinject tools/xinject.c -lX11
   Use:    /tmp/xinject <winid> <x> <y> <hold_us>

   NOTE: the event_mask here is the REAL X11 ButtonPressMask (1<<2). That
   mismatch is exactly what exposed D38 -- fenster.zig had been selecting
   1<<4 (EnterWindowMask) for buttons, so no client could ever deliver a
   button event to it. */
int main(int argc, char **argv) {
  if (argc < 5) { fprintf(stderr, "usage: inject <winid> <x> <y> <hold_us>\n"); return 2; }
  Window w = (Window)strtoul(argv[1], NULL, 0);
  int x = atoi(argv[2]), y = atoi(argv[3]);
  long hold = atol(argv[4]);
  Display *d = XOpenDisplay(NULL);
  if (!d) { fprintf(stderr, "no display\n"); return 1; }

  XEvent ev;
  memset(&ev, 0, sizeof ev);
  ev.xbutton.type = ButtonPress;
  ev.xbutton.display = d;
  ev.xbutton.window = w;
  ev.xbutton.root = RootWindow(d, DefaultScreen(d));
  ev.xbutton.x = x; ev.xbutton.y = y;
  ev.xbutton.x_root = x; ev.xbutton.y_root = y;
  ev.xbutton.button = Button1;
  ev.xbutton.state = 0;
  ev.xbutton.send_event = True;
  XSendEvent(d, w, False, ButtonPressMask, &ev);
  XFlush(d);
  usleep(hold);

  ev.xbutton.type = ButtonRelease;
  XSendEvent(d, w, False, ButtonReleaseMask, &ev);
  XFlush(d);
  XCloseDisplay(d);
  fprintf(stderr, "injected press+release at %d,%d\n", x, y);
  return 0;
}
