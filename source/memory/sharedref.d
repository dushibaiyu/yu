﻿module smartref.sharedref;

import core.atomic;
import std.experimental.allocator;
static import std.algorithm.mutation;
import std.traits;
import std.exception;

import smartref.util;
import smartref.common;


struct ISharedRef(Alloc,T)
{
	enum isShared = is(T == shared);
	alias ValueType = Pointer!T;
	alias Deleter = void function(ref Alloc,ValueType) nothrow;
	alias Data = ExternalRefCountData!(Alloc,isShared);
	alias DataWithDeleter = ExternalRefCountDataWithDeleter!(Alloc,ValueType,isShared);
	alias TWeakRef = IWeakRef!(Alloc,T);
	alias TSharedRef = ISharedRef!(Alloc,T);
	static if(is(T == class)){
		alias QEnableSharedFromThis = IEnableSharedFromThis!(Alloc,T);
	}
	enum isSaticAlloc = (stateSize!Alloc == 0);

	static if(isSaticAlloc) {
		this(ValueType ptr){
			internalConstruct(ptr,&defaultDeleter);
		}
		this(ValueType ptr,Deleter deleter){
			internalConstruct(ptr,deleter);
		}
	} else {
		this(Alloc alloc ,ValueType ptr){
			_alloc = alloc;
			internalConstruct(ptr,&defaultDeleter);
		}
		this(Alloc alloc ,ValueType ptr,Deleter deleter){
			_alloc = alloc;
			internalConstruct(ptr,deleter);
		}

		@property Alloc allocator(){return _alloc;}
	}

	this(ref TSharedRef sptr){
		this._ptr = sptr._ptr;
		this._dd = sptr._dd;
		if(_dd) {
			_dd.strongRef();
			_dd.weakRef();
		}
		static if(!isSaticAlloc)
			this._alloc = sptr._alloc;
	}

	this(ref TWeakRef wptr){
		internalSet(wptr._dd,wptr._alloc,wptr._ptr);
	}

	~this(){deref();}

	alias data this;

	@property ValueType data() {return _ptr;}
	@property bool isNull()const {return (_ptr is null);}

	pragma(inline)
	void swap(ref TSharedRef tref){
		std.algorithm.mutation.swap(tref._dd,this._dd);
		std.algorithm.mutation.swap(tref._ptr,this._ptr);
		static if(!isSaticAlloc)
			std.algorithm.mutation.swap(tref._alloc,this._alloc);
	}
	pragma(inline,true) void rest(){clear();}
	pragma(inline) void clear() { TSharedRef copy = TSharedRef.init; swap(copy);}
	static if(isSaticAlloc) {
		pragma(inline,true) void rest()(ValueType ptr){
			TSharedRef copy = TSharedRef(ptr); swap(copy);
		}
		pragma(inline,true) void rest()(ValueType ptr,Deleter deleter){
			TSharedRef copy = TSharedRef(ptr,deleter); swap(copy);
		}
	} else {
		pragma(inline,true) void rest()(Alloc alloc ,ValueType ptr){
			TSharedRef copy = TSharedRef(alloc,ptr); swap(copy);
		}
		pragma(inline,true) void rest()(Alloc alloc ,ValueType ptr,Deleter deleter){
			TSharedRef copy = TSharedRef(alloc,ptr,deleter); swap(copy);
		}
	}

	TWeakRef toWeakRef() {
		return TWeakRef(this);
	}

	auto castTo(U)() 
		if(is(U == shared) == isShared)
	{
		ISharedRef!(Alloc,U) result;
		if(isNull)
			return result;
		alias CastType = Pointer!U;
		CastType u = cast(CastType)_ptr;
		if(u !is null)
			result.internalSet(_dd,_alloc,u);
		return result;
	}

	void opAssign(ref TSharedRef rhs){
		TSharedRef copy = TSharedRef(rhs);
		swap(copy);
	}

	void opAssign(ref TWeakRef rhs){
		internalSet(rhs._dd,rhs._alloc,rhs._ptr);
	}

	void opAssign(TSharedRef rhs){
		swap(rhs);
	}

	static if (isPointer!ValueType) {
		ref T opUnary(string op)()
			if (op == "*")
		{
			return *_ptr;
		}
	}

private:

	static void defaultDeleter(ref Alloc alloc, ValueType value) nothrow {
		 collectException( alloc.dispose(value) );
	}

	void deref() nothrow{
		_ptr = null;
		deref(_dd,_alloc);
	}
	static void deref(ref Data dd, ref Alloc alloc) nothrow{
		if (!dd) return;
		if (!dd.strongDef()) {
			dd.free(alloc);
		}
		if (!dd.weakDef()){
			collectException(smartRefAllocator.dispose(dd));
			dd = null;
		}
	}
	void internalConstruct(ValueType ptr, Deleter deleter)
	{
		_ptr = ptr;
		if(ptr !is null) {
			_dd = smartRefAllocator.make!(DataWithDeleter)(ptr,deleter);
			static if(is(T == class) && isInheritClass!(T,QEnableSharedFromThis))
				_ptr.initializeFromSharedPointer(this);
		}
	}

	void internalSet(Data o,ref Alloc alloc, ValueType ptr){
		static if(!isSaticAlloc) {
			Alloc tmpalloc = _alloc;
			_alloc = alloc;
		} else {
			alias tmpalloc = Alloc.instance;
		}
		if(o){
			if(o.strongref > 0){
				o.strongRef();
				o.weakRef();
				_ptr = ptr;
			} else {
				_ptr = null;
				o = null;
			}
		}
		std.algorithm.mutation.swap(_dd,o);
		deref(o,tmpalloc);
	}
	ValueType _ptr;// 
	Data _dd;
	static if(!isSaticAlloc)
		Alloc _alloc ;
	else
		alias _alloc = Alloc.instance;
}

struct IWeakRef(Alloc,T)
{
	enum isShared = is(T == shared);
	alias ValueType = Pointer!T;
	alias Data = ExternalRefCountData!(Alloc, isShared);
	enum isSaticAlloc = (stateSize!Alloc == 0);
	alias TWeakRef = IWeakRef!(Alloc,T);
	alias TSharedRef = ISharedRef!(Alloc,T);

	this(ref TSharedRef tref){
		this._ptr = tref._ptr;
		this._dd = tref._dd;
		if(_dd) _dd.weakRef();
		static if(!isSaticAlloc)
			this._alloc = tref._alloc; 
	}

	this(ref TWeakRef tref){
		this._ptr = tref._ptr;
		this._dd = tref._dd;
		if(_dd) _dd.weakRef();
		static if(!isSaticAlloc)
			this._alloc = tref._alloc;
	}

	pragma(inline,true) bool isNull() { return (_dd is null || _ptr is null || _dd.strongref == 0); }
	pragma(inline,true) ValueType data() { return isNull()  ? null : _ptr; }
	pragma(inline) void clear() { TWeakRef copy = TWeakRef.init; swap(copy);}
	pragma(inline) void swap(ref TWeakRef tref) 
	{
		std.algorithm.mutation.swap(tref._dd,this._dd);
		std.algorithm.mutation.swap(tref._ptr,this._ptr);
		static if(!isSaticAlloc)
			std.algorithm.mutation.swap(tref._alloc,this._alloc);
	}

	pragma(inline,true) TSharedRef toStrongRef()  { return TSharedRef(this); }

	void opAssign(ref TWeakRef rhs){
		TWeakRef copy = TWeakRef(rhs);
		swap(copy);
	}
	
	void opAssign(ref TSharedRef rhs){
		internalSet(rhs._dd,rhs._alloc,rhs._ptr);
	}

	void opAssign(TWeakRef rhs){
		swap(rhs);
	}
	
private:
	void deref() nothrow
	{
		_ptr = null;
		if (!_dd) return;
		if (!_dd.weakDef()){
			collectException(smartRefAllocator.dispose(_dd));
			_dd = null;
		}
	}

	void internalSet(Data o,ref Alloc alloc,ValueType ptr){
		if (_dd is o) return;
		if (o) {
			o.weakRef();
			_ptr = ptr;
		}
		if (_dd && !_dd.weakDef())
			smartRefAllocator.dispose(_dd);
		_dd = o;
		static if(!isSaticAlloc) 
			_alloc = alloc;
	}
	
	ValueType _ptr; // 只为保留指针在栈中，如果指针是GC分配的内存，而ExternalRefCountData非GC的，则不用把非GC内存添加到GC的扫描列表中
	Data _dd;
	static if(!isSaticAlloc)
		Alloc _alloc;
	else
		alias _alloc = Alloc.instance;
}


interface IEnableSharedFromThis(Alloc,T)
{
	alias TWeakRef = IWeakRef!(Alloc,T);
	alias TSharedRef = ISharedRef!(Alloc,T);

	void initializeFromSharedPointer(ref TSharedRef ptr);
}

mixin template EnableSharedFromThisImpl()
{
public:
	pragma(inline,true)
	final TSharedRef sharedFromThis() { return TSharedRef(__weakPointer); }
//	pragma(inline,true)
//	final TSharedRef sharedFromThis() const { return TSharedRef(__weakPointer); }
	
	
	//pragma(inline,true)
	final override void initializeFromSharedPointer(ref TSharedRef ptr)
	{
		__weakPointer = ptr;
	}
private:
	TWeakRef __weakPointer;
}

private:


abstract class ExternalRefCountData(Alloc, bool isShared)
{
	pragma(inline,true) final int strongDef() nothrow {
		static if(isShared)
			return atomicOp!("-=")(_strongref,1);
		else 
			return -- _strongref;
	}
	
	
	pragma(inline,true) final int strongRef() nothrow{
		static if(isShared)
			return atomicOp!("+=")(_strongref,1);
		else
			return ++ _strongref;
	}
	
	pragma(inline,true) final int weakDef() nothrow {
		static if(isShared)
			return atomicOp!("-=")(_weakref,1);
		else
			return -- _weakref;
	}
	pragma(inline,true) final int weakRef() nothrow {
		static if(isShared)
			return atomicOp!("+=")(_weakref,1);
		else
			return ++ _weakref;
	}
	
	pragma(inline,true) final @property int weakref() nothrow{
		static if(isShared)
			return atomicLoad(_weakref);
		else
			return _weakref;
	}
	
	pragma(inline,true) final @property int strongref() nothrow{
		static if(isShared)
			return atomicLoad(_strongref);
		else
			return _strongref;
	}

	void free(ref Alloc alloc) nothrow;

	static if(isShared){
		shared int _weakref = 1;
		shared int _strongref = 1;
	} else {
		int _weakref = 1;
		int _strongref = 1;
	}
}

final class ExternalRefCountDataWithDeleter(Alloc,ValueType,bool isShared) : ExternalRefCountData!(Alloc,isShared)
{
	pragma(msg, "is  ahsred " ~ isShared.stringof);
	alias Deleter = void function(ref Alloc,ValueType) nothrow;
	
	this(ValueType ptr, Deleter dele){
		value = ptr;
		deleater = dele;
	}

	override void free(ref Alloc alloc) nothrow{
		if(deleater && value) 
			deleater(alloc,value);
		deleater = null;
		value = null;
	}
	
	Deleter  deleater;
	ValueType value;
}
