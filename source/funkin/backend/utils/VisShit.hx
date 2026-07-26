package funkin.backend.utils;

import flixel.math.FlxMath;
import flixel.sound.FlxSound;
import lime.utils.Int16Array;

using Lambda;

class VisShit
{
	public var snd:FlxSound;
	public var setBuffer:Bool = false;
	public var audioData:Int16Array;
	public var sampleRate:Int = 44100; // default, ez?
	public var numSamples:Int = 0;

	public function new(snd:FlxSound)
	{
		this.snd = snd;
	}

	public static function getCurAud(aud:Int16Array, index:Int):CurAudioInfo
	{
		var left = aud[index] / 32767;
		var right = aud[index + 2] / 32767;
		var balanced = (left + right) / 2;

		var funny:CurAudioInfo = {left: left, right: right, balanced: balanced};

		return funny;
	}

	public function checkAndSetBuffer()
	{
		if (snd != null && snd.playing)
		{
			if (!setBuffer)
			{
				// Math.pow3
				@:privateAccess
				var buf = snd._channel.__audioSource.buffer;

				// @:privateAccess
				audioData = cast buf.data; // jank and hacky lol! kinda busted on HTML5 also!!
				sampleRate = buf.sampleRate;

				setBuffer = true;
				numSamples = Std.int(audioData.length / 2);
			}
		}
	}
}

typedef CurAudioInfo =
{
	var left:Float;
	var right:Float;
	var balanced:Float;
}
