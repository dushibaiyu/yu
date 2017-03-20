﻿/*
 * Collie - An asynchronous event-driven network framework using Dlang development
 *
 * Copyright (C) 2015-2016  Shanghai Putao Technology Co., Ltd 
 *
 * Developer: putao's Dlang team
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module collie.socket.client.linkinfo;

import std.socket;
import std.traits : hasMember;
import collie.socket.tcpclient;

struct TLinkInfo(TCallBack,Manger = void) 
	if(is(TCallBack == delegate) && ( (is(Manger == class) && hasMember!(Manger,"connectCallBack") ) || is(Manger == void)))
{
	TCPClient client;
	Address addr;
	uint tryCount = 0;
	TCallBack cback;

	static if(!is(Manger == void)){
		Manger manger;
		void connectCallBack(bool state){
			if(manger)
				manger.connectCallBack(&this, state);
		}
	}

private:
	TLinkInfo!(TCallBack,Manger) * prev;
	TLinkInfo!(TCallBack,Manger) * next;
}

struct TLinkManger(TCallBack,Manger = void)
{
	alias LinkInfo = TLinkInfo!(TCallBack,Manger);

	void addInfo(LinkInfo * info)
	{
		if(info){
			info.next = _info.next;
			if(info.next){
				info.next.prev = info;
			}
			info.prev = &_info;
			_info.next = info;
		}
	}

	void rmInfo(LinkInfo * info)
	{
		info.prev.next = info.next;
		if (info.next)
			info.next.prev = info.prev;
		info.next = null;
		info.prev = null;
	}

private:
	LinkInfo _info;
}