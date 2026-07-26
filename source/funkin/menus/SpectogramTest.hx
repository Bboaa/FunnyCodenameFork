package funkin.menus;

import flixel.util.FlxColor;
import funkin.backend.utils.PolygonSpectogram;

class SpectogramTest extends MusicBeatState
{
	var viz:PolygonSpectogram;

	public override function create()
	{
		super.create();

		CoolUtil.playMenuSong(false);

		viz = new PolygonSpectogram(null, FlxColor.GREEN, 520, 1);
		viz.screenCenter();
		add(viz);
	}
}
