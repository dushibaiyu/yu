module yu.network.netinterface;

import yu.string;
import yu.container.vector;
import yu.container.string;

import std.experimental.allocator.mallocator;



struct AddressEntry
{
	string ip;
	string netmarsk;
	string broadcast;
	string gateway;
	ulong preferredLifetime = 0;
	ulong validityLifetime = 0;
	bool lifetimeKnown = false;

	this(ref AddressEntry other){

	}
}

class NetWorkInterface
{
	enum InterfaceFlag{
		IsUp = 0x1,
		IsRunning = 0x2,
        CanBroadcast = 0x4,
        IsLoopBack = 0x8,
        IsPointToPoint = 0x10,
        CanMulticast = 0x20
	}
	enum InterfaceType {
        Loopback = 1,
        Virtual,
        Ethernet,
        Slip,
        CanBus,
        Ppp,
        Fddi,
        Wifi,
        Ieee80211 = Wifi,   // alias
        Phonet,
        Ieee802154,
        SixLoWPAN,  // 6LoWPAN, but we can't start with a digit
        Ieee80216,
        Ieee1394,

        Unknown = 0
    }

	@property String name() {return _name;}
	@property String humanReadableName() {return _readname;}
	// @property InterfaceFlags flags() const {}
    // @property InterfaceType type() const;
    @property String hardwareAddress() {return _hardAddress;}
private:
	String _name;
	String _readname;
	String _hardAddress;
	Vector!(AddressEntry,Mallocator,false) _addressEntries;
}

