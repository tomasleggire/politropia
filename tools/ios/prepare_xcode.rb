#!/usr/bin/env ruby

# Agrega al proyecto Xcode generado por Godot los símbolos de compatibilidad
# requeridos por Godot 4.7.2 cuando se compila con Xcode 16.2 / iOS SDK 18.2.

require "fileutils"

root = File.expand_path("../..", __dir__)
source = File.join(__dir__, "sdk_compat_stubs.m")
ios_dir = File.join(root, "build", "ios")
destination = File.join(ios_dir, "politropia", "sdk_compat_stubs.m")
project = File.join(ios_dir, "politropia.xcodeproj", "project.pbxproj")

abort("Primero exportá el preset iOS desde Godot.") unless File.file?(project)

FileUtils.cp(source, destination)
contents = File.read(project)

unless contents.include?("sdk_compat_stubs.m in Sources")
  contents.sub!(
    "/* Begin PBXBuildFile section */",
    "/* Begin PBXBuildFile section */\n\t\tC0DE00010000000000000001 /* sdk_compat_stubs.m in Sources */ = {isa = PBXBuildFile; fileRef = C0DE00020000000000000002 /* sdk_compat_stubs.m */; };"
  )
  contents.sub!(
    "/* Begin PBXFileReference section */",
    "/* Begin PBXFileReference section */\n\t\tC0DE00020000000000000002 /* sdk_compat_stubs.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = sdk_compat_stubs.m; sourceTree = \"<group>\"; };"
  )
  contents.sub!(
    "\t\t\t\t1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */,",
    "\t\t\t\t1FF8DBB01FBA9DE1009DE660 /* dummy.cpp */,\n\t\t\t\tC0DE00020000000000000002 /* sdk_compat_stubs.m */,"
  )
  contents.sub!(
    "\t\t\t\t1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */,",
    "\t\t\t\t1FF8DBB11FBA9DE1009DE660 /* dummy.cpp in Sources */,\n\t\t\t\tC0DE00010000000000000001 /* sdk_compat_stubs.m in Sources */,"
  )
  File.write(project, contents)
end

contents = File.read(project)
contents.gsub!(/CODE_SIGN_IDENTITY = "Apple Distribution";/, 'CODE_SIGN_IDENTITY = "Apple Development";')
unless contents.include?("CODE_SIGN_STYLE = Automatic;")
  contents.gsub!(
    /CODE_SIGN_IDENTITY = "Apple Development";/,
    "CODE_SIGN_IDENTITY = \"Apple Development\";\n\t\t\t\tCODE_SIGN_STYLE = Automatic;\n\t\t\t\tDEVELOPMENT_TEAM = NN2XF448XH;"
  )
end
contents.gsub!(/DEVELOPMENT_TEAM = "";/, 'DEVELOPMENT_TEAM = NN2XF448XH;')
File.write(project, contents)

puts "Proyecto Xcode preparado: #{project}"
