module yu.time;

import std.compiler;
static if(version_minor > 74) {
    import std.datetime;
} else {
    import std.datetime.systime;
}

long sysToUinxTimeMs(ref SysTime time)
{
    return stdToUinxTimeMs(time.stdTime);
}

long stdToUinxTimeMs(long stdTime)
{
    return convert!("hnsecs", "msecs")(stdTime - 621_355_968_000_000_000L);
}
