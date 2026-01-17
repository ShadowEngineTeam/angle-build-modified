package;

import haxe.io.Path;

import sys.FileSystem;
import sys.io.File;

import util.ANSIUtil;
import util.FileUtil;

using StringTools;

class Build
{
	@:noCompletion
	static final ANGLE_HEADERS_FOLDERS:Array<String> = ['EGL', 'GLES2', 'GLES3', 'KHR'];

	@:noCompletion
	static final ANGLE_LIBS:Array<String> = ['libGLESv2', 'libEGL'];

	@:noCompletion
	static var buildPlatform:Null<String>;

	public static function run():Void
	{
		// Get the defined build platform.
		buildPlatform = Platform.getBuildPlatform();

		// Create the build dir.
		FileUtil.createDirectory('build');

		// Start the building proccess.
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

			final absBuildDir:String = Path.normalize(FileSystem.absolutePath('../build'));

			for (headersFolder in ANGLE_HEADERS_FOLDERS)
			{
				try
				{
					FileUtil.createDirectory('$absBuildDir/$buildPlatform/include/$headersFolder');
					FileUtil.copyDirectory('include/$headersFolder', '$absBuildDir/$buildPlatform/include/$headersFolder');
				}
				catch (e:Dynamic)
					Sys.println(ANSIUtil.apply('Failed to copy "$headersFolder" because: $e.', [ANSICode.Bold, ANSICode.Yellow]));
			}

			for (targetConfig in getBuildConfig())
			{
				FileUtil.createDirectory(targetConfig.getExportPath());

				File.saveContent(Path.join([targetConfig.getExportPath(), 'args.gn']), targetConfig.getAngleArgs().split(' ').join('\n'));

				if (buildPlatform == 'linux' && targetConfig.cpu == 'arm64')
					Sys.command('python', ['build/linux/sysroot_scripts/install-sysroot.py', '--arch=arm64']);

				if (Sys.command('gn', ['gen', targetConfig.getExportPath()]) != 0)
				{
					Sys.println(ANSIUtil.apply('Failed to build ${targetConfig.os}-${targetConfig.cpu}.', [ANSICode.Bold, ANSICode.Red]));
					Sys.exit(1);
				}

				if (Sys.command('autoninja', ['-C', targetConfig.getExportPath()].concat(ANGLE_LIBS)) == 0)
				{
					switch (buildPlatform)
					{
						case 'windows':
							for (file in FileSystem.readDirectory(targetConfig.getExportPath()))
							{
								for (lib in ANGLE_LIBS)
								{
									if (file.startsWith(lib))
									{
										if (Path.extension(file) == 'lib')
										{
											FileUtil.createDirectory('$absBuildDir/lib/${targetConfig.cpu}');

											File.copy('${targetConfig.getExportPath()}/$file', '$absBuildDir/lib/${targetConfig.cpu}/$file');
										}
										else if (Path.extension(file) == 'dll')
										{
											FileUtil.createDirectory('$absBuildDir/bin/${targetConfig.cpu}');

											File.copy('${targetConfig.getExportPath()}/$file', '$absBuildDir/bin/${targetConfig.cpu}/$file');
										}
									}
								}
							}
					}
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

		if (buildPlatform != null && buildPlatform.length > 0)
		{
			switch (buildPlatform)
			{
				case 'windows' | 'linux':
					final renderingBackends:Array<String> = [];

					renderingBackends.push('angle_enable_d3d9=false'); // Disable D3D9 backend
					renderingBackends.push('angle_enable_d3d11=false'); // Disable D3D11 backend
					renderingBackends.push('angle_enable_gl=false'); // Disable OpenGL backend
					renderingBackends.push('angle_enable_metal=false'); // Disable Metal backend
					renderingBackends.push('angle_enable_null=false'); // Disable Null backend
					renderingBackends.push('angle_enable_wgpu=false'); // Disable WebGPU backend

					renderingBackends.push('angle_enable_swiftshader=false'); // Disable SwiftShader

					renderingBackends.push('angle_enable_vulkan=true'); // Enable Vulkan backend
					renderingBackends.push('angle_enable_vulkan_api_dump_layer=false'); // Disable Vulkan API dump layer
					renderingBackends.push('angle_enable_vulkan_validation_layers=false'); // Disable Vulkan validation layers
					renderingBackends.push('angle_use_custom_libvulkan=false'); // Use system Vulkan loader only

					if (buildPlatform == 'windows')
					{
						final targetConfigX64:Config = getDefaultTargetPlatform();
						targetConfigX64.os = 'win';
						targetConfigX64.cpu = 'x64';
						targetConfigX64.args = targetConfigX64.args.concat(renderingBackends);
						targetConfigs.push(targetConfigX64);

						final targetConfigARM64:Config = getDefaultTargetPlatform();
						targetConfigARM64.os = 'win';
						targetConfigARM64.cpu = 'arm64';
						targetConfigARM64.args = targetConfigARM64.args.concat(renderingBackends);
						targetConfigs.push(targetConfigARM64);

						final targetConfigX86:Config = getDefaultTargetPlatform();
						targetConfigX86.os = 'win';
						targetConfigX86.cpu = 'x86';
						targetConfigX86.args = targetConfigX86.args.concat(renderingBackends);
						targetConfigs.push(targetConfigX86);
					}
					else
					{
						final targetConfigX64:Config = getDefaultTargetPlatform();
						targetConfigX64.os = 'linux';
						targetConfigX64.cpu = 'x64';
						targetConfigX64.args = targetConfigX64.args.concat(renderingBackends);
						targetConfigs.push(targetConfigX64);

						final targetConfigARM64:Config = getDefaultTargetPlatform();
						targetConfigARM64.os = 'linux';
						targetConfigARM64.cpu = 'arm64';
						targetConfigARM64.args = targetConfigARM64.args.concat(renderingBackends);
						targetConfigs.push(targetConfigARM64);
					}
			}
		}

		return targetConfigs;
	}

	public static function addAngleBuildOptimization(targetConfig:Config):Void
	{
		targetConfig.args.push('build_with_chromium=false');
		targetConfig.args.push('chrome_pgo_phase=0');
		targetConfig.args.push('dcheck_always_on=false');
		targetConfig.args.push('is_debug=false');
		targetConfig.args.push('is_official_build=true');
		targetConfig.args.push('strip_debug_info=true');
		targetConfig.args.push('symbol_level=0');
	}

	public static function addAngleClangSetup(targetConfig:Config):Void
	{
		targetConfig.args.push('is_clang=true');
		targetConfig.args.push('clang_use_chrome_plugins=false');
		targetConfig.args.push('use_custom_libcxx=false');
	}

	public static function addAngleSetup(targetConfig:Config):Void
	{
		targetConfig.args.push('angle_assert_always_on=false');
		targetConfig.args.push('angle_build_all=false');
		targetConfig.args.push('angle_build_tests=false');
		targetConfig.args.push('angle_has_frame_capture=false');
		targetConfig.args.push('angle_has_histograms=false');
		targetConfig.args.push('angle_has_rapidjson=false');
		targetConfig.args.push('angle_standalone=true');
	}

	public static function getDefaultTargetPlatform():Config
	{
		final targetConfig:Config = new Config();

		// Angle setup
		addAngleSetup(targetConfig);

		// Clang setup
		addAngleClangSetup(targetConfig);

		// Optimization
		addAngleBuildOptimization(targetConfig);

		return targetConfig;
	}
}
