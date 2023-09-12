module yu.time;

import std.datetime;

long sysToUinxTimeMs(ref SysTime time)  @trusted nothrow
{
    return stdToUinxTimeMs(time.stdTime);
}

long stdToUinxTimeMs(long stdTime)  @trusted nothrow
{
    return convert!("hnsecs", "msecs")(stdTime - 621_355_968_000_000_000L);
}
