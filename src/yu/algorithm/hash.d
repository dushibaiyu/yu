module yu.algorithm.hash;

import yu.traits : isCharByte;


@trusted @nogc pure uint SDBMHash(CHAR)(const CHAR[] str) if(isCharByte!CHAR)
{
    uint hash = 0;
    foreach(ch; str)// equivalent to: hash = 65599*hash + (*str++);
        hash = ch + (hash << 6) + (hash << 16) - hash;
    return (hash & 0x7FFFFFFF);
}

// RS Hash Function
@trusted @nogc pure int RSHash(CHAR)(const CHAR[] str) if(isCharByte!CHAR)
{
    uint b = 378551;
    uint a = 63689;
    uint hash = 0;

    foreach(ch; str)
    {
        hash = hash * a + ch;
        a *= b;
    }

    return (hash & 0x7FFFFFFF);
}

// JS Hash Function
@trusted @nogc pure uint JSHash(CHAR)(const CHAR[] str) if(isCharByte!CHAR)
{
    uint hash = 1315423911;

    foreach(ch; str)
        hash ^= ((hash << 5) + ch + (hash >> 2));

    return (hash & 0x7FFFFFFF);
}

// P. J. Weinberger Hash Function
@trusted @nogc pure uint PJWHash(CHAR)(const CHAR[] str) if(isCharByte!CHAR)
{
    enum BitsInUnignedInt  = cast(uint)(uint.sizeof * 8);
    enum ThreeQuarters    = cast(uint)((BitsInUnignedInt  * 3) / 4);
    enum OneEighth        = cast(uint)(BitsInUnignedInt / 8);
    enum HighBits         = cast(uint)(0xFFFFFFFF) << (BitsInUnignedInt - OneEighth);
    uint hash             = 0;
    uint test             = 0;

    foreach(ch; str)
    {
        hash = (hash << OneEighth) + ch;
        if ((test = hash & HighBits) != 0)
        {
            hash = ((hash ^ (test >> ThreeQuarters)) & (~HighBits));
        }
    }

    return (hash & 0x7FFFFFFF);
}

// ELF Hash Function
@trusted @nogc pure uint ELFHash(CHAR)(const CHAR[] str) if(isCharByte!CHAR)
{
    uint hash = 0;
    uint x    = 0;

    foreach(ch; str)
    {
        hash = (hash << 4) + ch;
        if ((x = hash & 0xF0000000L) != 0)
        {
            hash ^= (x >> 24);
            hash &= ~x;
        }
    }

    return (hash & 0x7FFFFFFF);
}

// BKDR Hash Function
@trusted @nogc pure uint BKDRHash(CHAR)(const CHAR[] str) if(isCharByte!CHAR)
{
    enum seed = 131; // 31 131 1313 13131 131313 etc..
    uint hash = 0;

    foreach(ch; str)
        hash = hash * seed + ch;

    return (hash & 0x7FFFFFFF);
}

// DJB Hash Function
@trusted @nogc pure uint DJBHash(CHAR)(const CHAR[] str) if(isCharByte!CHAR)
{
    uint hash = 5381;

    foreach(ch; str)
        hash += (hash << 5) + ch;

    return (hash & 0x7FFFFFFF);
}

// AP Hash Function
@trusted @nogc pure uint APHash(CHAR)(const CHAR[] str) if(isCharByte!CHAR)
{
    uint hash = 0;
    foreach(i,ch; str)
    {
        if ((i & 1) == 0)
            hash ^= ((hash << 7) ^ ch ^ (hash >> 3));
        else
            hash ^= (~((hash << 11) ^ ch ^ (hash >> 5)));
    }

    return (hash & 0x7FFFFFFF);
}

//Jenkins hash function one-at-a-time
@trusted @nogc pure uint JKOhash(CHAR)(const CHAR[] str) if(isCharByte!CHAR)
{
    uint hash = 0;
    foreach(ch; str)
    {
        hash += ch;
        hash += (hash << 10);
        hash ^= (hash >> 6);
    }
    hash += (hash << 3);
    hash ^= (hash >> 11);
    hash += (hash << 15);
    return hash;
}

@trusted @nogc pure size_t Murmur3Hash(CHAR)(const CHAR[] str, size_t seed = 0) if(isCharByte!CHAR)
{
    import core.internal.hash : bytesHash;
    return bytesHash(str.ptr, str.length,seed);
}

unittest {
    string hash = "tets hash!!!";
    const ubyte[] thash = cast(const ubyte[])hash;
    assert(SDBMHash(hash) == SDBMHash(thash));
    assert(RSHash(hash) == RSHash(thash));
    assert(JSHash(hash) == JSHash(thash));
    assert(PJWHash(hash) == PJWHash(thash));
    assert(BKDRHash(hash) == BKDRHash(thash));
    assert(DJBHash(hash) == DJBHash(thash));
    assert(APHash(hash) == APHash(thash));
    assert(JKOhash(hash) == JKOhash(thash));
    assert(Murmur3Hash(hash) == Murmur3Hash(thash));
}
