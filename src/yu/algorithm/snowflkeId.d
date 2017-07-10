module yu.algorithm.snowflkeId;

import std.datetime;
import core.atomic;
import core.thread;

/**
 * Twitter's Snowflke ID generate algorithm.to generate only ID
 * 
 * workerIdBits : 工作机器的ID所占的位数，支持不存在workID
 * seqBits ： 计数器位数，默认： 10个位用来保存计数码
 * twepoch :  开始的时间戳，ms。默认为 2017-3-1 0：0：0.0
*/

alias SnowflkeID = SnowflkeBase!(4);

final class SnowflkeBase(int workerIdBits, int sequenceBits = 10, long twepoch = 1488297600000L)
        if (sequenceBits > 0 && twepoch > 0)
{
    enum long maxSequence = -1L ^ -1L << sequenceBits; //一毫秒内可以产生计数，如果达到该值则等到下一微妙在进行生成
    static if (workerIdBits > 0)
    {
        enum long maxWorkerId = -1L ^ -1L << workerIdBits; //最大机器ID
        enum int timestampLeftShift = sequenceBits + workerIdBits; //时间戳左移动位数就是机器码和计数器位数
    }
    else
    {
        enum int timestampLeftShift = sequenceBits; //时间戳左移动位数就是机器码和计数器位数
    }

    static if (workerIdBits > 0)
    {
        this(long macid)
        in
        {
            assert(macid <= maxWorkerId && macid >= 0);
        }
        body
        {
            macId = macid;
        }

        @property MacId() const nothrow{return macId;}
    }

    long generate()
    {
        long timestamp;
        synchronized (this)
        {
            timestamp = Clock.currStdTime / 10000; // 获取毫秒数
            if (lastTime >= timestamp)
            {
                sequence += 1;
            }
            else
            {
                lastTime = timestamp;
                sequence = 0;
            }
            if (sequence > maxSequence)
            {
                while (true)
                {
                    timestamp = Clock.currStdTime / 10000; // 获取毫秒数
                    if (timestamp > lastTime)
                        break;
                }
                lastTime = timestamp;
                sequence = 0;
            }
        }
        static if (workerIdBits > 0)
        {
            return (((timestamp - twepoch) << timestampLeftShift) | (macId << sequenceBits)
                    | sequence);
        }
        else
        {
            return (((timestamp - twepoch) << timestampLeftShift) | sequence);
        }
    }

protected:
    void witeToNext()
    {
        while (true)
        {
            long timestamp = Clock.currStdTime / 10000; // 获取毫秒数
            if (timestamp > lastTime)
                return;
        }
    }

private:
    static if (workerIdBits > 0)
        long macId;
    long sequence = 0;
    long lastTime = 0;
}

unittest
{
    import std.stdio;

    SnowflkeID sny = new SnowflkeID(0);

    writeln("SnowflkeID : ", Clock.currStdTime);
    foreach (i; 0 .. 10000)
    {
        sny.generate();
    }
    writeln("SnowflkeID : end ", Clock.currStdTime);

    auto sny2 = new SnowflkeBase!(0,15)();
     writeln("SnowflkeID : ", Clock.currStdTime);
    foreach (i; 0 .. 10000)
    {
        sny.generate();
    }
    writeln("SnowflkeID : end ", Clock.currStdTime);
}
