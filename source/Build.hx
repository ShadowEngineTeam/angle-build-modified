package;

import haxe.io.Path;
import sys.io.File;

import util.ANSIUtil;

import sys.FileSystem;

import util.FileUtil;

class Build
{
	public static function run():Void
	{
		FileUtil.goAndBackFromDir('angle', function():Void
		{
			if (Sys.systemName() == 'Linux')
				Sys.command('build/install-build-deps.sh', []);

			if (!FileSystem.exists('chrome/VERSION'))
			{
				Sys.println(ANSIUtil.apply('Creating mock chrome VERSION file...', [ANSICode.Bold, ANSICode.Blue]));

				if (!FileSystem.exists('chrome'))
					FileUtil.createDirectory('chrome');

				final chromeFileContent:Array<String> = [];
				chromeFileContent.push('MAJOR=1');
				chromeFileContent.push('MINOR=0');
				chromeFileContent.push('BUILD=0');
				chromeFileContent.push('PATCH=0');
				File.saveContent('chrome/VERSION', chromeFileContent.join('\n'));
			}

			for (targetConfig in getBuildConfig())
			{
				FileUtil.createDirectory(targetConfig.getExportPath());

				File.saveContent(Path.join([targetConfig.getExportPath(), 'args.gn']), targetConfig.getAngleArgs().split(' ').join('\n'));

				if (Sys.command('gn', ['gen', targetConfig.getExportPath()]) == 0)
				{
					Sys.command('autoninja', ['-C', targetConfig.getExportPath(), 'libGLESv2', 'libEGL']);
				}
				else
				{
					Sys.println(ANSIUtil.apply('Failed to build ${targetConfig.os}-${targetConfig.cpu}.', [ANSICode.Bold, ANSICode.Red]));
					Sys.exit(1);
				}
			}
		});
	}

	public static function getBuildConfig():Array<Config>
	{
		final targetConfigs:Array<Config> = [];

		{
			final targetConfig:Config = new Config();
			targetConfig.os = 'win';
			targetConfig.cpu = 'x64';
			targetConfig.args.push('angle_build_all=false');
			targetConfig.args.push('angle_build_tests=false');
			targetConfig.args.push('angle_enable_d3d9=false');
			targetConfig.args.push('angle_enable_gl=false');
			targetConfig.args.push('angle_enable_null=false');
			targetConfig.args.push('angle_enable_swiftshader=false');
			targetConfig.args.push('angle_enable_vulkan=true');
			targetConfig.args.push('angle_enable_wgpu=false');
			targetConfig.args.push('angle_has_frame_capture=false');
			targetConfig.args.push('angle_standalone=true');
			targetConfig.args.push('build_with_chromium=false');
			targetConfig.args.push('chrome_pgo_phase=0');
			targetConfig.args.push('clang_use_chrome_plugins=false');
			targetConfig.args.push('dcheck_always_on=false');
			targetConfig.args.push('is_clang=true');
			targetConfig.args.push('is_debug=false');
			targetConfig.args.push('is_official_build=true');
			targetConfig.args.push('strip_debug_info=true');
			targetConfigs.push(targetConfig);
		}

		return targetConfigs;
	}
}
