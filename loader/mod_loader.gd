# ModLoader - A mod loader for GDScript
#
# Written in 2021 by harrygiel <harrygiel@gmail.com>,
# in 2021 by Mariusz Chwalba <mariusz@chwalba.net>,
# in 2022 by Vladimir Panteleev <git@cy.md>
#
# To the extent possible under law, the author(s) have
# dedicated all copyright and related and neighboring
# rights to this software to the public domain worldwide.
# This software is distributed without any warranty.
#
# You should have received a copy of the CC0 Public
# Domain Dedication along with this software. If not, see
# <http://creativecommons.org/publicdomain/zero/1.0/>.

extends Node

var MOD_LOG_PATH = "user://mods.log"
var areModsEnabled = false

func _init():
	for arg in OS.get_cmdline_args():
		if arg == "--enable-mods":
			areModsEnabled = true

	if !areModsEnabled && OS.has_feature("standalone"):
		return

	mod_log("ModLoader: Loading mods...")
	_loadMods()
	mod_log("ModLoader: Done loading mods.")

	mod_log("ModLoader: Initializing mods...")
	_initMods()
	mod_log("ModLoader: Done initializing mods.")


var _modZipFiles = []

func mod_log(text:String)->void :
	var date_time = Time.get_datetime_dict_from_system()
	var date_time_string = str(date_time.day,'.',date_time.month,'.',date_time.year,' - ', date_time.hour,':',date_time.minute,':',date_time.second)
	
	print(str(date_time_string,'   ', text))
	
	var log_file = File.new()
	
	if(!log_file.file_exists(MOD_LOG_PATH)):
		log_file.open(MOD_LOG_PATH, File.WRITE)
		log_file.store_string("\n" + str(date_time_string,'   ', 'Created mod.log!'))
		log_file.close()
	
	var _error = log_file.open(MOD_LOG_PATH, File.READ_WRITE)
	if(_error):
		print(_error)
		return
	log_file.seek_end()
	log_file.store_string("\n" + str(date_time_string,'   ', text))
	log_file.close()

func _loadMods():
	var gameInstallDirectory = OS.get_executable_path().get_base_dir()
	mod_log(str("gameInstallDirectory: ", gameInstallDirectory))
	if OS.get_name() == "OSX":
		gameInstallDirectory = gameInstallDirectory.get_base_dir().get_base_dir().get_base_dir()
	var modPathPrefix = gameInstallDirectory.plus_file("mods")

	var dir = Directory.new()
	if dir.open(modPathPrefix) != OK:
		mod_log("ModLoader: Can't open mod folder %s." % modPathPrefix)
		return
	if dir.list_dir_begin() != OK:
		mod_log("ModLoader: Can't read mod folder %s." % modPathPrefix)
		return

	while true:
		var fileName = dir.get_next()
		if fileName == '':
			break
		if dir.current_is_dir():
			continue
		var modFSPath = modPathPrefix.plus_file(fileName)
		var modGlobalPath = ProjectSettings.globalize_path(modFSPath)
		if !ProjectSettings.load_resource_pack(modGlobalPath, true):
			mod_log("ModLoader: %s failed to load." % fileName)
			continue
		_modZipFiles.append(modFSPath)
		mod_log("ModLoader: %s loaded." % fileName)
	dir.list_dir_end()


# Load and run any ModMain.gd scripts which were present in mod ZIP files.
# Attach the script instances to this singleton's scene to keep them alive.
func _initMods():
	var initScripts = []
	for modFSPath in _modZipFiles:
		var gdunzip = load('res://vendor/gdunzip.gd').new()
		gdunzip.load(modFSPath)
		for modEntryPath in gdunzip.files:
			var modEntryName = modEntryPath.get_file().to_lower()
			if modEntryName.begins_with('modmain') and modEntryName.ends_with('.gd'):
				var modGlobalPath = "res://" + modEntryPath
				mod_log("ModLoader: Loading %s" % modGlobalPath)
				var packedScript = ResourceLoader.load(modGlobalPath)
				initScripts.append(packedScript)

	initScripts.sort_custom(self, "_compareScriptPriority")

	for packedScript in initScripts:
		mod_log("ModLoader: Running %s" % packedScript.resource_path)
		var scriptInstance = packedScript.new(self)
		scriptInstance.name = packedScript.resource_path.split('/')[2]
		add_child(scriptInstance, true)


func _compareScriptPriority(a, b):
	var aPrio = a.get_script_constant_map().get("MOD_PRIORITY", 0)
	var bPrio = b.get_script_constant_map().get("MOD_PRIORITY", 0)
	if aPrio != bPrio:
		return aPrio < bPrio

	# Ensure that the result is deterministic, even when the priority is the same
	var aPath = a.resource_path
	var bPath = b.resource_path
	if aPath != bPath:
		return aPath < bPath

	return false


func installScriptExtension(childScriptPath:String):
	var childScript = ResourceLoader.load(childScriptPath)

	# Force Godot to compile the script now.
	# We need to do this here to ensure that the inheritance chain is
	# properly set up, and multiple mods can chain-extend the same
	# class multiple times.
	# This is also needed to make Godot instantiate the extended class
	# when creating singletons.
	# The actual instance is thrown away.
	childScript.new()

	var parentScript = childScript.get_base_script()
	var parentScriptPath = parentScript.resource_path
	mod_log("ModLoader: Installing script extension: %s <- %s" % [parentScriptPath, childScriptPath])
	childScript.take_over_path(parentScriptPath)


func addTranslationsFromCSV(csvPath: String):
	mod_log(str("ModLoader: adding translations from CSV -> ", csvPath))
	var translationCsv = File.new()
	translationCsv.open(csvPath, File.READ)
	var TranslationParsedCsv = {}

	var translations = []

	# Load the header line
	var csvLine = translationCsv.get_csv_line()
	for i in range(1, csvLine.size()):
		var translationObject = Translation.new()
		translationObject.locale = csvLine[i]
		translations.append(translationObject)

	# Load translations
	while !translationCsv.eof_reached():
		csvLine = translationCsv.get_csv_line()
		if csvLine.size() == 1 and csvLine[0] == "":
			break  # Work around weird race condition in Godot leading to infinite loop
		var translationID = csvLine[0]
		for i in range(1, csvLine.size()):
			translations[i - 1].add_message(translationID, csvLine[i])

	translationCsv.close()

	# Install the translation objects
	for translationObject in translations:
		TranslationServer.add_translation(translationObject)
	
	mod_log(str("ModLoader: added translations from CSV -> ", csvPath))


func appendNodeInScene(modifiedScene, nodeName:String = "", nodeParent = null, instancePath:String = "", isVisible:bool = true):
	var newNode
	if instancePath != "":
		newNode = load(instancePath).instance()
	else:
		newNode = Node.instance()
	if nodeName != "":
		newNode.name = nodeName
	if isVisible == false:
		newNode.visible = false
	if nodeParent != null:
		var tmpNode = modifiedScene.get_node(nodeParent)
		tmpNode.add_child(newNode)
		newNode.set_owner(modifiedScene)
	else:
		modifiedScene.add_child(newNode)
		newNode.set_owner(modifiedScene)

# Things to keep to ensure they are not garbage collected
var _savedObjects = []

func saveScene(modifiedScene, scenePath:String):
	var packed_scene = PackedScene.new()
	packed_scene.pack(modifiedScene)
	mod_log(str("ModLoader: packing scene -> ", packed_scene))
	mod_log(str("ModLoader: scene childs -> ", packed_scene.instance().get_children()))
	packed_scene.take_over_path(scenePath)
	mod_log(str("ModLoader: saveScene - taking over path - new path -> ", packed_scene.resource_path))
	_savedObjects.append(packed_scene)
