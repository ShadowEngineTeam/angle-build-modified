package;

import haxe.io.Path;

import sys.FileSystem;
import sys.io.File;

import util.ANSIUtil;
import util.FileUtil;
import util.ProcessUtil;

class Setup
{
	public static function run():Void
	{
		if (Sys.systemName() == 'Windows')
		{
			Sys.putEnv('DEPOT_TOOLS_WIN_TOOLCHAIN', '0');

			Sys.putEnv('vs2022_install', 'C:\\Program Files\\Microsoft Visual Studio\\2022\\BuildTools');
		}

		if (!ProcessUtil.commandExists('git'))
		{
			Sys.println(ANSIUtil.apply('Git is not installed. Please install it first.', [ANSICode.Bold, ANSICode.Red]));
			Sys.exit(1);
		}

		if (!FileSystem.exists('export'))
			FileSystem.createDirectory('export');

		FileUtil.moveToDir('export');

		if (FileSystem.exists('angle') && FileSystem.exists('depot_tools'))
		{
			// Add depot_tools to PATH.
			addToPATH(FileSystem.absolutePath('depot_tools'));
			return;
		}

		// Clone or Update depot_tools.
		clone('depot_tools', 'https://chromium.googlesource.com/chromium/tools/depot_tools.git');

		// Add depot_tools to PATH.
		addToPATH(FileSystem.absolutePath('depot_tools'));

		// Clone or Update angle.
		clone('angle', 'https://chromium.googlesource.com/angle/angle');

		// Configure and sync ANGLE dependencies
		FileUtil.goAndBackFromDir('angle', function():Void
		{
			// Configure and sync ANGLE dependencies
			Sys.println(ANSIUtil.apply('Configuring gclient...', [ANSICode.Bold, ANSICode.Blue]));

			Sys.command('gclient', ['config', '--unmanaged', 'https://chromium.googlesource.com/angle/angle']);

			// Create a .gclient file with proper setup
			Sys.println(ANSIUtil.apply('Configuring `.gclient` file...', [ANSICode.Bold, ANSICode.Blue]));

			final gclientFile:Array<String> = [];

			gclientFile.push('solutions = [');
			gclientFile.push('  {');
			gclientFile.push('     "name": ".",');
			gclientFile.push('     "url": "https://chromium.googlesource.com/angle/angle",');
			gclientFile.push('     "deps_file": "DEPS",');
			gclientFile.push('     "managed": False,');
			gclientFile.push('  }');
			gclientFile.push(']');

			File.saveContent('.gclient', gclientFile.join('\n'));

			// Syncing ANGLE dependencies with gclient...
			Sys.command('gclient', ['sync', '--no-history', '--shallow', '--jobs', '8']);

			Sys.println(ANSIUtil.apply('ANGLE setup complete!', [ANSICode.Bold, ANSICode.Blue]));
		});
	}

	static function clone(name:String, url:String):Void
	{
		if (!FileSystem.exists(name))
		{
			Sys.println(ANSIUtil.apply('Cloning $name...', [ANSICode.Bold, ANSICode.Blue]));

			Sys.command('git', ['clone', '--depth', '1', url]);
		}
	}

	static function addToPATH(string:String):Void
	{
		if (Path.isAbsolute(string))
		{
			if (Sys.systemName() == 'Windows')
				Sys.putEnv('PATH', [string, Sys.getEnv('PATH')].join(';'));
			else
				Sys.putEnv('PATH', [string, Sys.getEnv('PATH')].join(':'));
		}
	}
}
