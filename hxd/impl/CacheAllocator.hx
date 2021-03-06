package hxd.impl;
import hxd.impl.Allocator;

private class Cache<T> {
	public var content : Array<T> = [];
	public var lastUse : Float = haxe.Timer.stamp();
	public var onDispose : T -> Void;
	public function new( ?dispose ) {
		onDispose = dispose;
	}
	public inline function get() {
		var b = content.pop();
		if( content.length == 0 ) lastUse = haxe.Timer.stamp();
		return b;
	}
	public inline function put(v) {
		content.push(v);
	}
	public function gc() {
		var b = content.pop();
		if( b == null ) return false;
		if( onDispose != null ) onDispose(b);
		lastUse += 1;
		return true;
	}
}

class CacheAllocator extends Allocator {

	var buffers = new Map<Int,Cache<h3d.Buffer>>();
	var indexBuffers = new Map<Int,Cache<h3d.Indexes>>();
	var lastGC = haxe.Timer.stamp();
	/**
	 * How long do we keep some buffer than hasn't been used in memory (in seconds, default 60)
	**/
	public var maxKeepTime = 60.;

	override function allocBuffer(vertices:Int, stride:Int, flags:BufferFlags):h3d.Buffer {
		if( vertices >= 65536 ) throw "assert";
		var id = flags.toInt() | (stride << 3) | (vertices << 16);
		var c = buffers.get(id);
		if( c != null ) {
			var b = c.get();
			if( b != null ) return b;
		}
		checkGC();
		return super.allocBuffer(vertices,stride,flags);
	}

	override function disposeBuffer(b:h3d.Buffer) {
		var f = b.flags;
		var flags = f.has(RawFormat) ? (f.has(Quads) ? RawQuads : RawFormat) : (f.has(UniformBuffer) ? UniformDynamic : Dynamic);
		var id = flags.toInt() | (b.buffer.stride << 3) | (b.vertices << 16);
		var c = buffers.get(id);
		if( c == null ) {
			c = new Cache(function(b:h3d.Buffer) b.dispose());
			buffers.set(id, c);
		}
		c.put(b);
		checkGC();
	}

	override function allocIndexBuffer( count : Int ) {
		var id = count;
		var c = indexBuffers.get(id);
		if( c != null ) {
			var i = c.get();
			if( i != null ) return i;
		}
		checkGC();
		return super.allocIndexBuffer(count);
	}

	override function disposeIndexBuffer( i : h3d.Indexes ) {
		var id = i.count;
		var c = indexBuffers.get(id);
		if( c == null ) {
			c = new Cache(function(i:h3d.Indexes) i.dispose());
			indexBuffers.set(id, c);
		}
		c.put(i);
		checkGC();
	}

	override function onContextLost() {
		buffers = new Map();
	}

	public function checkGC() {
		var t = haxe.Timer.stamp();
		if( t - lastGC > maxKeepTime * 0.1 ) gc();
	}

	public function gc() {
		var now = haxe.Timer.stamp();
		for( b in buffers.keys() ) {
			var c = buffers.get(b);
			if( now - c.lastUse > maxKeepTime && !c.gc() )
				buffers.remove(b);
		}
		lastGC = now;
	}

}
