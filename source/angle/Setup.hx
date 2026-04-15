package angle;

import haxe.io.Path;

import sys.FileSystem;
import sys.io.File;

import angle.util.ANSIUtil;
import angle.util.FileUtil;

class Setup
{
	static final ANGLE_COMMIT:String = '0fe2ac00168e8116a4d2f909326ab54bf1032ec4';

	public static function run():Void
	{
		if (Sys.systemName() == 'Windows')
		{
			// We need to set DEPOT_TOOLS_WIN_TOOLCHAIN to 0 for non-Googlers.
			Sys.putEnv('DEPOT_TOOLS_WIN_TOOLCHAIN', '0');
		}

		// Surpress Chromium development Git warnings.
		Sys.command('git', ['config', '--global', 'depot-tools.allowGlobalGitConfig', 'false']);

		// Create the export folder.
		if (!FileSystem.exists('export'))
			FileSystem.createDirectory('export');

		// Go to the export folder.
		FileUtil.moveToDir('export');

		// Print
		Sys.println(ANSIUtil.apply('Angle setup starting...', [ANSICode.Bold, ANSICode.Blue]));

		// Clone depot_tools.
		gitClone('depot_tools', 'https://chromium.googlesource.com/chromium/tools/depot_tools.git');

		// Add depot_tools to PATH.
		addToPATH(FileSystem.absolutePath('depot_tools'));

		// Clone angle.
		gitClone('angle', 'https://chromium.googlesource.com/angle/angle', false);

		// Configure and sync ANGLE dependencies
		FileUtil.goAndBackFromDir('angle', function():Void
		{
			final platform:String = Platform.getBuildPlatform();

			// Hard-pin ANGLE to a specific commit
			Sys.command('git', ['checkout', ANGLE_COMMIT]);

			// Configure and sync ANGLE dependencies
			Sys.command('gclient', ['config', '--unmanaged', 'https://chromium.googlesource.com/angle/angle']);

			{
				// Create a .gclient file with proper setup
				final gclientFile:Array<String> = [];
				gclientFile.push('solutions = [');
				gclientFile.push('  {');
				gclientFile.push('     "name": ".",');
				gclientFile.push('     "url": "https://chromium.googlesource.com/angle/angle",');
				gclientFile.push('     "deps_file": "DEPS",');
				gclientFile.push('     "managed": False,');
				gclientFile.push('  }');
				gclientFile.push(']');
				gclientFile.push('');
				if (platform == 'windows')
					gclientFile.push('target_os = ["win"]');
				else if (platform == 'linux')
					gclientFile.push('target_os = ["linux"]');
				else if (platform == 'mac')
					gclientFile.push('target_os = ["mac"]');
				else if (platform == 'android')
					gclientFile.push('target_os = ["android"]');
				else if (platform == 'ios')
					gclientFile.push('target_os = ["ios"]');
				File.saveContent('.gclient', gclientFile.join('\n'));
			}

			// Syncing ANGLE dependencies with gclient...
			Sys.command('gclient', ['sync', '--no-history', '--jobs', '8']);
			Sys.command('gclient', ['runhooks']);

			if (platform == 'windows')
				FileUtil.goAndBackFromDir('third_party/SwiftShader/third_party/llvm-10.0', function():Void
				{
					Sys.command("sed -i '/SuccIterator(InstructionT \\*Inst)/i\\  SuccIterator() : Inst(nullptr), Idx(0) {}' llvm/include/llvm/IR/CFG.h");
				});

			FileUtil.applyGitPatchesFromDir('../../patches');
		});

		// Print
		Sys.println(ANSIUtil.apply('Angle setup complete!', [ANSICode.Bold, ANSICode.Blue]));
	}

	@:noCompletion
	static function gitClone(name:String, url:String, shallow:Bool = true):Void
	{
		if (!FileSystem.exists(name))
			Sys.command('git', shallow ? ['clone', '--depth', '1', url] : ['clone', url]);
	}

	@:noCompletion
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
