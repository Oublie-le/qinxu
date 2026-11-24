#!/usr/bin/env python3
"""Generate the small iOS Xcode project without a third-party project generator."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "PianoPractice.xcodeproj"

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def q(value):
    return json.dumps(str(value), ensure_ascii=False)

objects = []
def obj(name, value):
    objects.append(f"\t\t{uid(name)} = {{ {value} }};")
    return uid(name)

sources = sorted((ROOT / "Sources/PianoApp").rglob("*.swift"))
refs, builds = [], []
for path in sources:
    relative = path.relative_to(ROOT).as_posix()
    ref = obj("file:" + relative, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(relative)}; sourceTree = SOURCE_ROOT;")
    refs.append(ref)
    builds.append(obj("build:" + relative, f"isa = PBXBuildFile; fileRef = {ref};"))

product = obj("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PianoPractice.app; sourceTree = BUILT_PRODUCTS_DIR;')
plist = obj("plist", 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Config/Info.plist; sourceTree = SOURCE_ROOT;')
source_group = obj("source-group", f"isa = PBXGroup; children = ({','.join(refs)},); name = App; sourceTree = \"<group>\";")
products_group = obj("products-group", f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
root_group = obj("root-group", f'isa = PBXGroup; children = ({source_group},{plist},{products_group},); sourceTree = "<group>";')
local_package = obj("local-package", 'isa = XCLocalSwiftPackageReference; relativePath = .;')
core_product = obj("core-product", f'isa = XCSwiftPackageProductDependency; package = {local_package}; productName = PianoCore;')
core_build = obj("core-build", f'isa = PBXBuildFile; productRef = {core_product};')
source_phase = obj("source-phase", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
framework_phase = obj("framework-phase", f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({core_build},); runOnlyForDeploymentPostprocessing = 0;')
resource_phase = obj("resource-phase", 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')

project_configs, target_configs = [], []
for name in ("Debug", "Release"):
    project_settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if name == "Debug" else "",
        "ENABLE_TESTABILITY": "YES" if name == "Debug" else "NO"
    }
    target_settings = {
        "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "0.1.0",
        "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "Config/Info.plist",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.ifeng.PianoPractice", "PRODUCT_NAME": "$(TARGET_NAME)",
        "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO", "SWIFT_EMIT_LOC_STRINGS": "YES",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"
    }
    for prefix, settings, collection in (("project", project_settings, project_configs), ("target", target_settings, target_configs)):
        values = " ".join(f"{key} = {q(value)};" for key, value in settings.items())
        collection.append(obj(f"{prefix}-{name}", f'isa = XCBuildConfiguration; buildSettings = {{ {values} }}; name = {name};'))

project_list = obj("project-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target_list = obj("target-configs", f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj("target", f'isa = PBXNativeTarget; buildConfigurationList = {target_list}; buildPhases = ({source_phase},{framework_phase},{resource_phase},); buildRules = (); dependencies = (); name = PianoPractice; packageProductDependencies = ({core_product},); productName = PianoPractice; productReference = {product}; productType = "com.apple.product-type.application";')
root = obj("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.0; }}; }}; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (en,zh_CN,Base,); mainGroup = {root_group}; packageReferences = ({local_package},); productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')

PROJECT.mkdir(exist_ok=True)
(PROJECT / "project.pbxproj").write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {root};\n}}\n')
schemes = PROJECT / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="PianoPractice.app" BlueprintName="PianoPractice" ReferencedContainer="container:PianoPractice.xcodeproj"/>'
(schemes / "PianoPractice.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f"Generated {PROJECT} with {len(sources)} app source files")
