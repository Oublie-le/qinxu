#!/usr/bin/env python3
"""Generate the small iOS Xcode project without a third-party project generator."""
from pathlib import Path
import hashlib
import json
import sys

CHECK = "--check" in sys.argv

def write_generated(path, content):
    if CHECK:
        if not path.exists() or path.read_text() != content:
            raise SystemExit(f"Outdated project file: {path}. Run python3 scripts/generate_project.py")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "QinXu.xcodeproj"

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def q(value):
    return json.dumps(str(value), ensure_ascii=False)

objects = []
def obj(name, value):
    objects.append(f"\t\t{uid(name)} = {{ {value} }};")
    return uid(name)

sources = sorted((ROOT / "Sources/QinXuApp").rglob("*.swift"))
refs, builds = [], []
for path in sources:
    relative = path.relative_to(ROOT).as_posix()
    ref = obj("file:" + relative, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(relative)}; sourceTree = SOURCE_ROOT;")
    refs.append(ref)
    builds.append(obj("build:" + relative, f"isa = PBXBuildFile; fileRef = {ref};"))

ui_sources = sorted((ROOT / "UITests").rglob("*.swift"))
ui_refs, ui_builds = [], []
for path in ui_sources:
    relative = path.relative_to(ROOT).as_posix()
    ref = obj("file:" + relative, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(relative)}; sourceTree = SOURCE_ROOT;")
    ui_refs.append(ref)
    ui_builds.append(obj("build:" + relative, f"isa = PBXBuildFile; fileRef = {ref};"))
ui_product = obj("ui-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = QinXuUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
ui_group = obj("ui-group", f'isa = PBXGroup; children = ({",".join(ui_refs)},); name = UITests; sourceTree = "<group>";')
ui_source_phase = obj("ui-sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(ui_builds)},); runOnlyForDeploymentPostprocessing = 0;')
ui_framework_phase = obj("ui-frameworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
# iOS uses a flat app bundle. A root directory literally named Resources can
# make codesign interpret the app as another bundle format. Copy these children.
resource_builds = []
for name, file_type in [("Assets.xcassets", "folder.assetcatalog"),
                        ("BasicPitch.mlpackage", "folder"), ("Books", "folder"), ("Fonts", "folder"),
                        ("BasicPitch-LICENSE.txt", "text"), ("BasicPitch-NOTICE.txt", "text")]:
    relative = "Sources/QinXuApp/Resources/" + name
    resource_ref = obj("resource:" + name, f'isa = PBXFileReference; lastKnownFileType = {file_type}; path = {q(relative)}; sourceTree = SOURCE_ROOT;')
    refs.append(resource_ref)
    resource_builds.append(obj("resource-build:" + name, f'isa = PBXBuildFile; fileRef = {resource_ref};'))
product = obj("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = QinXu.app; sourceTree = BUILT_PRODUCTS_DIR;')
plist = obj("plist", 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Config/Info.plist; sourceTree = SOURCE_ROOT;')
signing = obj("signing-config", 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/Signing.xcconfig; sourceTree = SOURCE_ROOT;')
source_group = obj("source-group", f"isa = PBXGroup; children = ({','.join(refs)},); name = App; sourceTree = \"<group>\";")
products_group = obj("products-group", f'isa = PBXGroup; children = ({product},{ui_product},); name = Products; sourceTree = "<group>";')
root_group = obj("root-group", f'isa = PBXGroup; children = ({source_group},{ui_group},{plist},{signing},{products_group},); sourceTree = "<group>";')
local_package = obj("local-package", 'isa = XCLocalSwiftPackageReference; relativePath = .;')
core_product = obj("core-product", f'isa = XCSwiftPackageProductDependency; package = {local_package}; productName = QinXuCore;')
core_build = obj("core-build", f'isa = PBXBuildFile; productRef = {core_product};')
source_phase = obj("source-phase", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
framework_phase = obj("framework-phase", f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({core_build},); runOnlyForDeploymentPostprocessing = 0;')
resource_phase = obj("resource-phase", f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resource_builds)},); runOnlyForDeploymentPostprocessing = 0;')

project_configs, target_configs, ui_configs = [], [], []
for name in ("Debug", "Release"):
    project_settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if name == "Debug" else "",
        "ENABLE_TESTABILITY": "YES" if name == "Debug" else "NO",
        "ONLY_ACTIVE_ARCH": "YES" if name == "Debug" else "NO"
    }
    target_settings = {
        "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "0.1.0",
        "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "Config/Info.plist",
        "PRODUCT_BUNDLE_IDENTIFIER": "$(QINXU_BUNDLE_IDENTIFIER)", "PRODUCT_NAME": "$(TARGET_NAME)",
        "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO", "SWIFT_EMIT_LOC_STRINGS": "YES",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"
    }
    ui_settings = {
        "CODE_SIGN_STYLE": "Automatic", "GENERATE_INFOPLIST_FILE": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": "$(QINXU_BUNDLE_IDENTIFIER).UITests", "PRODUCT_NAME": "$(TARGET_NAME)",
        "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "TEST_TARGET_NAME": "QinXu", "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": "YES",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"
    }
    for prefix, settings, collection in (("project", project_settings, project_configs), ("target", target_settings, target_configs), ("ui", ui_settings, ui_configs)):
        values = " ".join(f"{key} = {q(value)};" for key, value in settings.items())
        base_config = f"baseConfigurationReference = {signing}; " if prefix == "project" else ""
        collection.append(obj(f"{prefix}-{name}", f'isa = XCBuildConfiguration; {base_config}buildSettings = {{ {values} }}; name = {name};'))

project_list = obj("project-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target_list = obj("target-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj("target", f'isa = PBXNativeTarget; buildConfigurationList = {target_list}; buildPhases = ({source_phase},{framework_phase},{resource_phase},); buildRules = (); dependencies = (); name = QinXu; packageProductDependencies = ({core_product},); productName = QinXu; productReference = {product}; productType = "com.apple.product-type.application";')
ui_config_list = obj("ui-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(ui_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
ui_proxy = obj("ui-proxy", f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = QinXu;')
ui_dependency = obj("ui-dependency", f'isa = PBXTargetDependency; target = {target}; targetProxy = {ui_proxy};')
ui_target = obj("ui-target", f'isa = PBXNativeTarget; buildConfigurationList = {ui_config_list}; buildPhases = ({ui_source_phase},{ui_framework_phase},); buildRules = (); dependencies = ({ui_dependency},); name = QinXuUITests; productName = QinXuUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing";')
root = obj("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.0; }}; {ui_target} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {target}; }}; }}; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (en,zh_CN,Base,); mainGroup = {root_group}; packageReferences = ({local_package},); productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = ({target},{ui_target},);')

write_generated(PROJECT / "project.pbxproj", '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {root};\n}}\n')
schemes = PROJECT / "xcshareddata/xcschemes"
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="QinXu.app" BlueprintName="QinXu" ReferencedContainer="container:QinXu.xcodeproj"/>'
ui_reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="QinXuUITests.xctest" BlueprintName="QinXuUITests" ReferencedContainer="container:QinXu.xcodeproj"/>'
write_generated(schemes / "QinXu.xcscheme", f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{ui_reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO" parallelizable="NO">{ui_reference}</TestableReference></Testables><MacroExpansion>{reference}</MacroExpansion></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f"{'Verified' if CHECK else 'Generated'} {PROJECT} with {len(sources)} app source files")
