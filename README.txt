This is a library for talking to PolyComp <http://www.polycomp.co.uk> LED
signs using their 'GTXC' serial protocol. Not all sign features are
supported yet (notably, I have made no attempt to allow for using the
message scheduling features) and currently, it is set up to work best with
2-line signs (the kind I have).

There is no real documentation yet, but see the example code at the bottom
of the script.

This library is a work in progress. Some things may not work quite right,
and some cleanup is needed (I need to switch from talking directly to a TTY
device file, to a library like Ruby/SerialPort or similar). Also, there will
probably eventually be some kind of (optional) locking to deal with
contention if multiple processes want to use the sign.
