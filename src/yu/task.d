module yu.task;

import std.traits;
import std.experimental.allocator;
import std.variant;
import core.atomic;

ReturnType!F run(F, Args...)(F fpOrDelegate, ref Args args) {
    return fpOrDelegate(args);
}

enum TaskStatus : ubyte {
    LDLE = 0x00,
    Runing = 0x01,
    Finsh = 0x02,
    InVaild = 0x03,
}

@trusted class AbstractTask {
    alias TaskFun = bool function(AbstractTask);

    final bool job() {
        if (atomicLoad(_status) != TaskStatus.LDLE)
            return false;
        atomicStore(_status, TaskStatus.Runing);
        scope (failure)
            atomicStore(_status, TaskStatus.InVaild);
        bool rv = false;
        if (_runTask)
            rv = _runTask(this);
        if (rv)
            atomicStore(_status, TaskStatus.Finsh);
        else
            atomicStore(_status, TaskStatus.InVaild);
        return rv;
    }

    final bool rest() {
        if (isRuning)
            return false;
        atomicStore(_status, TaskStatus.LDLE);
        return true;
    }

    final @property TaskStatus status() {
        return atomicLoad(_status);
    }

    pragma(inline, true) final bool isRuning() {
        return (atomicLoad(_status) == TaskStatus.Runing);
    }

    Variant rvalue;
protected:
    this(TaskFun fun) {
        _runTask = fun;
    }

private:
    TaskFun _runTask;
    shared TaskStatus _status = TaskStatus.LDLE;
    AbstractTask next;
}

@trusted final class Task(alias fun, Args...) : AbstractTask {
    static if (Args.length > 0) {
        this(Args args) {
            _args = args;
            super(&impl);
        }

        Args _args;
    } else {
        this() {
            super(&impl);
        }

        alias _args = void;
    }

    static bool impl(AbstractTask myTask) {
        auto myCastedTask = cast(typeof(this)) myTask;
        if (myCastedTask is null)
            return false;
        alias RType = typeof(fun(_args));
        static if (is(RType == void))
            fun(myCastedTask._args);
        else
            myCastedTask.rvalue = fun(myCastedTask._args);
        return true;
    }
}

@trusted auto makeTask(alias fun, Alloc, Args...)(Alloc alloc, Args args) {
    return make!(Task!(fun, Args))(alloc, args);
}

@trusted auto makeTask(F, Alloc, Args...)(Alloc alloc, F delegateOrFp, Args args) if (
        is(typeof(delegateOrFp(args)))) {
    return make!(Task!(run, F, Args))(alloc, delegateOrFp, args);
}

///Note:from GC
@trusted auto newTask(alias fun, Args...)(Args args) {
    return new Task!(fun, Args)(args);
}

///Note:from GC
@trusted auto newTask(F, Args...)(F delegateOrFp, Args args) if (is(typeof(delegateOrFp(args)))) {
    return new Task!(run, F, Args)(delegateOrFp, args);
}

struct TaskQueue {
    AbstractTask front() nothrow {
        return _frist;
    }

    bool empty() nothrow {
        return _frist is null;
    }

    void enQueue(AbstractTask task) nothrow
    in {
        assert(task);
    }
    body {
        if (_last) {
            _last.next = task;
        } else {
            _frist = task;
        }
        task.next = null;
        _last = task;
    }

    AbstractTask deQueue() nothrow
    in {
        assert(_frist && _last);
    }
    body {
        AbstractTask task = _frist;
        _frist = _frist.next;
        if (_frist is null)
            _last = null;
        return task;
    }

private:
    @disable this(this);
    AbstractTask _last = null;
    AbstractTask _frist = null;
}

unittest {
    int tfun() {
        return 10;
    }

    AbstractTask test = newTask(&tfun);
    assert(test.status == TaskStatus.LDLE);
    test.job();
    int a = test.rvalue.get!int();
    assert(test.status == TaskStatus.Finsh);
    assert(a == 10);
}
