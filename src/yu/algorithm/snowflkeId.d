module yu.algorithm.snowflkeId;

import std.datetime;
import core.atomic;
import core.thread;

/**
 * Twitter's Snowflke ID generate algorithm.to generate only ID
*/
enum long twepoch = 1488297600000L; //唯一时间，这是一个避免重复的随机量，自行设定不要大于当前时间戳， 默认为 2017-3-1 0：0：0.0
enum int workerIdBits = 4; //机器码字节数。4个字节用来保存机器码
enum long maxWorkerId = -1L ^ -1L << workerIdBits; //最大机器ID
enum int sequenceBits = 10; //计数器字节数，10个字节用来保存计数码
enum long maxSequence = -1L ^ -1L << sequenceBits; //一微秒内可以产生计数，如果达到该值则等到下一微妙在进行生成
enum int workerIdShift = sequenceBits; //机器码数据左移位数，就是后面计数器占用的位数
enum int timestampLeftShift = sequenceBits + workerIdBits; //时间戳左移动位数就是机器码和计数器总字节数

final class SnowflkeID {
    this(long macid) {
        setMacId(macid);
    }

    void setMacId(long macid)
    in {
        assert(macid <= maxWorkerId && macid >= 0);
    }
    body {
        macId = macid;
    }

    long generate() {
        long timestamp;
        synchronized (this) {
            timestamp = Clock.currStdTime / 10000; // 获取毫秒数
            if (lastTime >= timestamp) {
                sequence += 1;
            } else {
                lastTime = timestamp;
                sequence = 0;
            }
            if (sequence > maxSequence) { // 如果生成的ID过大，就线程休眠1ms，然后重新获取
                while (true) {
                    timestamp = Clock.currStdTime / 10000; // 获取毫秒数
                    if (timestamp > lastTime)
                        break;
                }
                lastTime = timestamp;
                sequence = 0;
            }
        }
        return (((timestamp - twepoch) << timestampLeftShift) | (macId << workerIdShift) | sequence);
    }

protected:
    void witeToNext() {
        while (true) {
            long timestamp = Clock.currStdTime / 10000; // 获取毫秒数
            if (timestamp > lastTime)
                return;
        }
    }

private:
    long macId;
    long sequence = 0;
    long lastTime = 0;
}

unittest {
    import std.stdio;

    SnowflkeID sny = new SnowflkeID(0);

    writeln("SnowflkeID : ", Clock.currStdTime);
    foreach (i; 0 .. 10000) {
        sny.generate();
    }
    writeln("SnowflkeID : end ", Clock.currStdTime);
}
