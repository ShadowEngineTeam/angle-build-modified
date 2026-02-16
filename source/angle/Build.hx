package angle;

import angle.util.ANSIUtil;
import angle.util.FileUtil;

import haxe.io.Path;

import sys.FileSystem;
import sys.io.File;

using StringTools;

class Build
{
	@:noCompletion
	static final ANGLE_HEADERS_FOLDERS:Array<String> = ['EGL', 'GLES2', 'GLES3', 'KHR'];

	@:noCompletion
	static final ANGLE_LIBS:Array<String> = ['libGLESv2', 'libEGL'];

	@:noCompletion
	static var buildPlatform:String = '';

	@:noCompletion
	static var buildConfigs:Array<Config> = [];

	public static function run():Void
	{
		// Get the defined build platform.
		buildPlatform = Platform.getBuildPlatform();

		// Get the defined build configs.
		buildConfigs = Build.getBuildConfig();

		// Create the build dir.
		FileUtil.createDirectory('build');

		// Print
		Sys.println(ANSIUtil.apply('Angle build started...', [ANSICode.Bold, ANSICode.Blue]));

		// Start the building proccess.
		FileUtil.goAndBackFromDir('angle', function():Void
		{
			if (Sys.systemName() == 'Linux')
				Sys.command('build/install-build-deps.sh', []);

			if (!FileSystem.exists('chrome/VERSION'))
			{
				Sys.println(ANSIUtil.apply('Creating mock chrome VERSION file...', [ANSICode.Bold, ANSICode.Blue]));

				FileUtil.createDirectory('chrome');

				final chromeFileContent:Array<String> = [];
				chromeFileContent.push('MAJOR=1');
				chromeFileContent.push('MINOR=0');
				chromeFileContent.push('BUILD=0');
				chromeFileContent.push('PATCH=0');
				File.saveContent('chrome/VERSION', chromeFileContent.join('\n'));
			}

			for (targetConfig in buildConfigs)
			{
				FileUtil.createDirectory(targetConfig.getExportPath());

				File.saveContent(Path.join([targetConfig.getExportPath(), 'args.gn']), targetConfig.getAngleArgs().split(' ').join('\n'));

				if (buildPlatform == 'linux' && targetConfig.cpu == 'arm64')
					Sys.command('python3', ['build/linux/sysroot_scripts/install-sysroot.py', '--arch=arm64']);

				if (buildPlatform == 'linux' && targetConfig.cpu == 'arm')
					Sys.command('python3', ['build/linux/sysroot_scripts/install-sysroot.py', '--arch=arm']);

				if (Sys.command('gn', ['gen', targetConfig.getExportPath()]) != 0)
				{
					Sys.println(ANSIUtil.apply('Failed to build ${targetConfig.os}-${targetConfig.cpu}.', [ANSICode.Bold, ANSICode.Red]));
					Sys.exit(1);
				}

				if (Sys.command('autoninja', ['-C', targetConfig.getExportPath()].concat(ANGLE_LIBS)) != 0)
				{
					Sys.println(ANSIUtil.apply('Failed to build ${targetConfig.os}-${targetConfig.cpu}.', [ANSICode.Bold, ANSICode.Red]));
					Sys.exit(1);
				}
			}
		});

		// Copy angle's headers.
		for (headersFolder in ANGLE_HEADERS_FOLDERS)
			FileUtil.copyDirectory('angle/include/$headersFolder', 'build/$buildPlatform/include/$headersFolder');

		// The macos libs that will be made an universal version of.
		final macosLibsToCombine:Map<String, Array<String>> = [];

		// The ios frameworks that will be made an universal version of based on the enviroment.
		final iosFrameworksToCombine:Map<String, Map<String, Array<String>>> = [];

		// Copy angle's libs.
		for (buildConfig in buildConfigs)
		{
			final libsToCopy:Array<String> = ANGLE_LIBS;

			if (buildPlatform == 'windows')
				libsToCopy.push('d3dcompiler_47');

			for (lib in libsToCopy)
			{
				switch (buildPlatform)
				{
					case 'windows':
						final dllLibFile:String = 'angle/${buildConfig.getExportPath()}/$lib.dll.lib';

						if (FileSystem.exists(dllLibFile))
							FileUtil.copyFile(dllLibFile, 'build/$buildPlatform/lib/${buildConfig.cpu}/$lib.dll.lib');

						FileUtil.copyFile('angle/${buildConfig.getExportPath()}/$lib.dll', 'build/$buildPlatform/bin/${buildConfig.cpu}/$lib.dll');
					case 'linux':
						FileUtil.copyFile('angle/${buildConfig.getExportPath()}/$lib.so', 'build/$buildPlatform/lib/${buildConfig.cpu}/$lib.so');
					case 'android':
						FileUtil.copyFile('angle/${buildConfig.getExportPath()}/${lib}_angle.so', 'build/$buildPlatform/lib/${buildConfig.cpu}/${lib}_angle.so');
					case 'macos':
						if (!macosLibsToCombine.exists(lib))
							macosLibsToCombine.set(lib, new Array<String>());

						final libDestination:String = 'build/$buildPlatform/lib/${buildConfig.cpu}/$lib.dylib';

						{
							FileUtil.copyFile('angle/${buildConfig.getExportPath()}/$lib.dylib', libDestination);

							Sys.command('install_name_tool', ['-id', '@rpath/$lib.dylib', libDestination]);
						}

						macosLibsToCombine.get(lib)?.push(libDestination);
					case 'ios':
						if (!iosFrameworksToCombine.exists(lib))
							iosFrameworksToCombine.set(lib, []);

						@:nullSafety(Off)
						if (!iosFrameworksToCombine.get(lib)?.exists(buildConfig.environment))
							iosFrameworksToCombine.get(lib)?.set(buildConfig.environment, new Array<String>());

						final libDestination:String = 'build/$buildPlatform/lib/${buildConfig.environment}/${buildConfig.cpu}/$lib.framework';

						FileUtil.copyDirectory('angle/${buildConfig.getExportPath()}/$lib.framework', libDestination);

						iosFrameworksToCombine.get(lib)?.get(buildConfig.environment)?.push(libDestination);
				}
			}
		}

		if (buildPlatform == 'macos')
		{
			for (libName => libsPaths in macosLibsToCombine)
			{
				final universalLibDestination:String = 'build/$buildPlatform/lib/universal/$libName.dylib';

				FileUtil.createDirectory(Path.directory(universalLibDestination));

				if (Sys.command('lipo', ['-create', '-output', universalLibDestination].concat(libsPaths)) == 0)
					Sys.command('install_name_tool', ['-id', '@rpath/$libName.dylib', universalLibDestination]);
				else
					Sys.println(ANSIUtil.apply('Failed to create universal lib for "$libName".', [ANSICode.Bold, ANSICode.Yellow]));
			}
		}
		else if (buildPlatform == 'ios')
		{
			final iosFrameworksToXCFramework:Map<String, Array<String>> = [];

			for (libName => libEnviroment in iosFrameworksToCombine)
			{
				if (!iosFrameworksToXCFramework.exists(libName))
					iosFrameworksToXCFramework.set(libName, new Array<String>());

				for (libEnviromentName => libEnviromentLibs in libEnviroment)
				{
					if (libEnviromentLibs.length >= 2)
					{
						final universalLibDestination:String = 'build/$buildPlatform/lib/$libEnviromentName/universal/$libName.framework';

						FileUtil.createDirectory(Path.directory(Path.addTrailingSlash(universalLibDestination)));

						{
							final frameworksToMerge:Array<String> = [];

							for (framework in libEnviromentLibs)
								frameworksToMerge.push('$framework/$libName');

							if (Sys.command('lipo', ['-create', '-output', '$universalLibDestination/$libName'].concat(frameworksToMerge)) != 0)
								Sys.println(ANSIUtil.apply('Failed to create universal lib for "$libName".', [ANSICode.Bold, ANSICode.Yellow]));
						}

						iosFrameworksToXCFramework.get(libName)?.push(universalLibDestination);
					}
					else
					{
						iosFrameworksToXCFramework.get(libName)?.push(libEnviromentLibs[0]);
					}
				}
			}

			for (frameworkName => frameworkPaths in iosFrameworksToXCFramework)
			{
				final universalFrameworkDestination:String = 'build/$buildPlatform/lib/universal/$frameworkName.xcframework';

				FileUtil.createDirectory(Path.directory(universalFrameworkDestination));

				final frameworksToMerge:Array<String> = [];

				for (framework in frameworkPaths)
				{
					frameworksToMerge.push('-framework');
					frameworksToMerge.push(framework);
				}

				Sys.command('xcodebuild', ['-create-xcframework'].concat(frameworksToMerge).concat(['-output', universalFrameworkDestination]));
			}
		}

		// Print
		Sys.println(ANSIUtil.apply('Angle build complete!', [ANSICode.Bold, ANSICode.Green]));
	}

	@:noCompletion
	static function getBuildConfig():Array<Config>
	{
		final targetConfigs:Array<Config> = [];

		if (buildPlatform != null && buildPlatform.length > 0)
		{
			switch (buildPlatform)
			{
				case 'windows' | 'linux' | 'android':
					final renderingBackends:Array<String> = [];

					/*if (buildPlatform != 'windows')
					{*/
						renderingBackends.push('angle_enable_gl=true'); // Enable OpenGL backend
					/*}
					else
					{
						renderingBackends.push('angle_enable_gl=false'); // Disable OpenGL backend
					}*/
					renderingBackends.push('angle_enable_metal=false'); // Disable Metal backend
					renderingBackends.push('angle_enable_null=false'); // Disable Null backend
					renderingBackends.push('angle_enable_wgpu=false'); // Disable WebGPU backend
					renderingBackends.push('angle_enable_swiftshader=false'); // Disable SwiftShader

					if (buildPlatform == 'windows')
					{
						renderingBackends.push('angle_enable_d3d9=true'); // Enable D3D9 backend
						renderingBackends.push('angle_enable_d3d11=true'); // Enable D3D11 backend
					}
					else
					{
						renderingBackends.push('angle_enable_d3d9=false'); // Disable D3D9 backend
						renderingBackends.push('angle_enable_d3d11=false'); // Disable D3D11 backend
					}

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
					else if (buildPlatform == 'linux')
					{
						final targetConfigX86:Config = getDefaultTargetPlatform();
						targetConfigX86.os = 'linux';
						targetConfigX86.cpu = 'x86';
						targetConfigX86.args = targetConfigX86.args.concat(renderingBackends);
						targetConfigs.push(targetConfigX86);

						final targetConfigX64:Config = getDefaultTargetPlatform();
						targetConfigX64.os = 'linux';
						targetConfigX64.cpu = 'x64';
						targetConfigX64.args = targetConfigX64.args.concat(renderingBackends);
						targetConfigs.push(targetConfigX64);

						final targetConfigARM:Config = getDefaultTargetPlatform();
						targetConfigARM.os = 'linux';
						targetConfigARM.cpu = 'arm';
						targetConfigARM.args = targetConfigARM.args.concat(renderingBackends);
						targetConfigs.push(targetConfigARM);

						final targetConfigARM64:Config = getDefaultTargetPlatform();
						targetConfigARM64.os = 'linux';
						targetConfigARM64.cpu = 'arm64';
						targetConfigARM64.args = targetConfigARM64.args.concat(renderingBackends);
						targetConfigs.push(targetConfigARM64);
					}
					else if (buildPlatform == 'android')
	                {
	                    final targetConfigARM:Config = getDefaultTargetPlatform();
	                    targetConfigARM.os = 'android';
	                    targetConfigARM.cpu = 'arm';
	                    targetConfigARM.args = targetConfigARM.args.concat(renderingBackends);
	                    targetConfigs.push(targetConfigARM);

	                    final targetConfigARM64:Config = getDefaultTargetPlatform();
	                    targetConfigARM64.os = 'android';
	                    targetConfigARM64.cpu = 'arm64';
	                    targetConfigARM64.args = targetConfigARM64.args.concat(renderingBackends);
	                    targetConfigs.push(targetConfigARM64);

	                    final targetConfigX86:Config = getDefaultTargetPlatform();
	                    targetConfigX86.os = 'android';
	                    targetConfigX86.cpu = 'x86';
	                    targetConfigX86.args = targetConfigX86.args.concat(renderingBackends);
	                    targetConfigs.push(targetConfigX86);

	                    final targetConfigX64:Config = getDefaultTargetPlatform();
	                    targetConfigX64.os = 'android';
	                    targetConfigX64.cpu = 'x64';
	                    targetConfigX64.args = targetConfigX64.args.concat(renderingBackends);
	                    targetConfigs.push(targetConfigX64);
	                }
				case 'macos' | 'ios':
					final renderingBackends:Array<String> = [];

					renderingBackends.push('angle_enable_d3d9=false'); // Disable D3D9 backend
					renderingBackends.push('angle_enable_d3d11=false'); // Disable D3D11 backend
					if (buildPlatform != 'ios')
					{
						renderingBackends.push('angle_enable_gl=true'); // Enable OpenGL backend
					}
					else 
					{
						renderingBackends.push('angle_enable_gl=false'); // Disable OpenGL backend
					}
					renderingBackends.push('angle_enable_metal=true'); // Enable Metal backend
					renderingBackends.push('angle_enable_null=false'); // Disable Null backend
					renderingBackends.push('angle_enable_wgpu=false'); // Disable WebGPU backend
					renderingBackends.push('angle_enable_vulkan=false'); // Disable Vulkan backend
					renderingBackends.push('angle_enable_swiftshader=false'); // Disable SwiftShader

					if (buildPlatform == 'macos')
					{
						final targetConfigARM64:Config = getDefaultTargetPlatform();
						targetConfigARM64.os = 'mac';
						targetConfigARM64.cpu = 'arm64';
						targetConfigARM64.args = targetConfigARM64.args.concat(renderingBackends);
						targetConfigs.push(targetConfigARM64);

						final targetConfigX64:Config = getDefaultTargetPlatform();
						targetConfigX64.os = 'mac';
						targetConfigX64.cpu = 'x64';
						targetConfigX64.args = targetConfigX64.args.concat(renderingBackends);
						targetConfigs.push(targetConfigX64);
					}
					else
					{
						final targetConfigDeviceARM64:Config = getDefaultTargetPlatform();
						targetConfigDeviceARM64.os = 'ios';
						targetConfigDeviceARM64.cpu = 'arm64';
						targetConfigDeviceARM64.environment = 'device';
						targetConfigDeviceARM64.args = targetConfigDeviceARM64.args.concat(renderingBackends);
						targetConfigs.push(targetConfigDeviceARM64);

						final targetConfigSimulatorARM64:Config = getDefaultTargetPlatform();
						targetConfigSimulatorARM64.os = 'ios';
						targetConfigSimulatorARM64.cpu = 'arm64';
						targetConfigSimulatorARM64.environment = 'simulator';
						targetConfigSimulatorARM64.args = targetConfigSimulatorARM64.args.concat(renderingBackends);
						targetConfigs.push(targetConfigSimulatorARM64);

						final targetConfigSimulatorX64:Config = getDefaultTargetPlatform();
						targetConfigSimulatorX64.os = 'ios';
						targetConfigSimulatorX64.cpu = 'x64';
						targetConfigSimulatorX64.environment = 'simulator';
						targetConfigSimulatorX64.args = targetConfigSimulatorX64.args.concat(renderingBackends);
						targetConfigs.push(targetConfigSimulatorX64);
					}
			}
		}

		return targetConfigs;
	}

	@:noCompletion
	static function addAngleBuildOptimization(targetConfig:Config):Void
	{
		targetConfig.args.push('build_with_chromium=false');
		targetConfig.args.push('chrome_pgo_phase=0');
		targetConfig.args.push('dcheck_always_on=false');

		if (buildPlatform == 'linux')
			targetConfig.args.push('is_cfi=false');

		targetConfig.args.push('is_debug=false');
		targetConfig.args.push('is_official_build=true');
		if (buildPlatform != 'android')
		{
		    targetConfig.args.push('strip_debug_info=true');
		    targetConfig.args.push('symbol_level=0');
		}
		else
		{
		    targetConfig.args.push('strip_debug_info=false');
		    targetConfig.args.push('symbol_level=1');
		}
	}

	@:noCompletion
	static function addAngleClangSetup(targetConfig:Config):Void
	{
		targetConfig.args.push('is_clang=true');
		targetConfig.args.push('clang_use_chrome_plugins=false');
		targetConfig.args.push('use_custom_libcxx=false');

		if (buildPlatform == 'ios')
			targetConfig.args.push('ios_enable_code_signing=false');
		else if (buildPlatform == 'android')
			targetConfig.args.push('android_ndk_api_level=24');
	}

	@:noCompletion
	static function addAngleSetup(targetConfig:Config):Void
	{
		targetConfig.args.push('angle_assert_always_on=false');
		targetConfig.args.push('angle_build_all=false');
		targetConfig.args.push('angle_build_tests=false');
		targetConfig.args.push('angle_has_frame_capture=false');
		targetConfig.args.push('angle_has_histograms=false');
		targetConfig.args.push('angle_has_rapidjson=false');
		targetConfig.args.push('angle_has_astc_encoder=false');
		targetConfig.args.push('angle_standalone=true');

		if (buildPlatform == 'android')
		{
			final androidSdk:String = Sys.getEnv("ANDROID_HOME");
			final androidNdk:String = Sys.getEnv("ANDROID_NDK_HOME");

			if (androidSdk == null || androidNdk == null) {
			    Sys.println(ANSIUtil.apply("ANDROID_HOME or ANDROID_NDK_HOME is not set.", [ANSICode.Bold, ANSICode.Red]));
			    Sys.exit(1);
			}

			targetConfig.args.push('android_sdk_root="$androidSdk"');
			targetConfig.args.push('android_ndk_root="$androidNdk"');
		}
	}

	@:noCompletion
	static function getDefaultTargetPlatform():Config
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
