This is a near complete implementation of unix "ls" that
is capable of sorting directories with thousands of entries.

TODO:

* Add different list styles
  Currently -l is always generated

* Change listing format depending on column width

* Add filename formatting with flag characters
  and filename colouring.

* Parse the LS_COLOR environment variable for
  colouring information.  Currently this environment
  variable and TIME_STYLE are both read but only
  TIME_STYLE is processed.

NOTES:

The output format is limited to -l for now and chosen to
fit in 32 columns.  The default is to list 8.3 filenames.

Try a variation like this one in 64 column mode:

.ls --gdf -AR --time-style=locale --lfn=on

USE OF MEMORY

A directory queue is maintained in two 8k pages and is
always paged entirely into memory at mmu6 and mmu7 when
accessed.  The queue is fifo and exists in a circular
buffer occupying the 16k.  In recursive mode, directories
that need to be visited are pushed into this queue.  And
as directories are listed, they are popped out of the queue.

An obstack holding file pointer records is held in main
memory from the end of the program (around address 43000)
to the top of memory.  Each file pointer record is a three-
byte pointer, the first byte indicating 8k page number and
the remaining two being a pointer into the page when it is
present in mmu7.  These file pointer records are fixed size
and grow like an expanding array so are easily sortable with
quicksort.  About 6000 records can be stored in main memory
allowing sorting of directories containing up to 6000 files.

Each file pointer record points at an actual file record.
These records are stored in extra 8k pages called LFN_PAGES.
A file record records 8.3 and lfn names, as well as time and
size information.  An individual record is variable in size
because the lfn name is variable in size.  Each page storing
records is managed by an obstack which will allocate memory
as needed.  The number of pages available is statically
compiled into the program and is currently four which means
32k is available to store file records.  Realistically this
places a much lower limit on the max number of files that
can be read from a directory at once, ie less than 6000.
If the limit is reached, the directory listing is split into
pieces.  If more space is needed, more pages can be allocated
by changing a constant and re-building the program.

Utilities like .ls must co-exist with basic, as in they must
not disturb basic's state.  This means .ls must allocate memory
from the operating system to load into and it must deallocate
that memory on exit.  All tasks are taken care of automatically
when z88dk builds this type of dot command called "dotn".

aralbrec@z88dk.org
