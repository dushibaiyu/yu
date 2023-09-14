Yu(玉)
[![Build Status](https://travis-ci.org/dushibaiyu/yu.svg?branch=master)](https://travis-ci.org/dushibaiyu/yu)
---------------------------------
        A Dlang's Toolkit. Extend Phobos.

------------------------------

* algorithm
* * snowflkeId.d : Twitter's Snowflke ID generate algorithm.to generate only ID
* * hash.d : string hash function
* * checksum.d : CRC, LRC , Fletcher, Adler...... check function
* container : the container base std.experimental.allocator
* * cirularqueue : Cirular Queue Struct Template.
* * vector : Like as C++'s std::vector
* * string :  The COW string template.
* timer :  Timer
* * timingwheeltimer :  Time wheel algorithm . base std.experimental.allocator
* memory
* * alloctor : the yuAlloctor and easy make object base yuAlloctor. Base  std.experimental.allocator
* * gc :  gcFree to easy free the memory in GC
* * scopedref :  the Unique Ptr/Ref like C++'s  std::unique_ptr.
* * sharedref : the RC Ptr/Ref like C++'s std::shared_ptr
* * smartref : easy to create the scopedref and sharedref
* array : Extend Phobos's std.array.
* bytes : add find in byte or ubyte.
* exception : Extend Phobos's std.exception.
* functional :  add bind use delegate.
* string : Extend Phobos's std.string.
* task : the task base  std.experimental.allocator
* thread :  auto attach thread
* traits : : Extend Phobos's std.traits.
* tools
* * http1xparser :  the http 1.x and url parser. Base and Port from : [https://github.com/nodejs/http-parser](https://github.com/nodejs/http-parser)
* * buffer : the buffer class.
* * sharedlib : load dll or so, in runing
* * serialize : a Custom binary-system serialize and deserialize

