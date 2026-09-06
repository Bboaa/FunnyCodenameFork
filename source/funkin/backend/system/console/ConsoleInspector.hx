package funkin.backend.system.console;

//WIP

import lime.tools.imgui.ImGuiFlags;
import flixel.math.FlxMatrix;
import flixel.math.FlxPoint;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.backend.scripting.HScript;
import funkin.backend.scripting.ScriptPack;
import lime.tools.imgui.ImGuiFlags.ImGuiTreeNodeFlags;
import funkin.game.Stage;
import flixel.FlxState;
import openfl.Lib;

#if IMGUI_ENABLED
import lime.tools.imgui.ImGuiTypes;
import lime.tools.imgui.ImGuiTypes.ImTextureID;
import lime.tools.imgui.ImGuiFlags.ImGuiSliderFlags;
import lime.tools.imgui.ImGuiPtr.ImGuiFloatPtr;
import lime.tools.imgui.ImGuiPtr.ImGuiIntPtr;
import lime.tools.imgui.ImGuiPtr.ImGuiBoolPtr;
import lime.tools.imgui.ImGuiPtr.ImGuiFloat4Ptr;
import lime.tools.imgui.ImGuiPtr.ImGuiStringPtr;
#end
#if foxlite
import foxlite.FoxScene;
import foxlite.group.FoxTypedGroup;
import foxlite.group.FoxObjectGroup;
import foxlite.FoxBasic;
import foxlite.FoxObject;
import foxlite.FoxModel;
#end

typedef InspectorObject = {
	var obj:Dynamic;
	var name:String;
	var type:String;
	var members:Array<InspectorObject>;
	var memberIndex:Int;
	var ?groupParent:InspectorObject;
}

class ConsoleInspector {

	var hscript:ConsoleHscript;
	var cachedInstanceFields:Map<String, Array<String>> = [];
	public function new(hscript:ConsoleHscript) {
		this.hscript = hscript;
	}

	#if IMGUI_ENABLED
	var selectedObject:Dynamic = null;
	var selectedObjectData:InspectorObject = null;
	var selectedObjectValidThisFrame:Bool = false;

	var currentStateObjects:Array<InspectorObject> = [];
	var inspectorObjectsThatNeedUpdating:Array<InspectorObject> = [];

	function updateObjects() {
		var states:Array<FlxState> = [FlxG.state];
		var stateToCheck:FlxState = FlxG.state;
		while(stateToCheck.subState != null) {
			states.push(stateToCheck.subState);
			stateToCheck = stateToCheck.subState;
		}
		
		if (currentStateObjects.length > states.length) {
			currentStateObjects.resize(states.length);
		}
		for (index => state in states) {
			if (currentStateObjects[index] == null || currentStateObjects[index].obj != state) {

				var packageName = hscript.getFieldTypeName(state);
				if (!cachedInstanceFields.exists(packageName)) {
					cachedInstanceFields.set(packageName, Type.getInstanceFields(Type.getClass(state)));
				}
				var packageSplit = packageName.split(".");
				var stateName = packageSplit[packageSplit.length-1];

				currentStateObjects[index] = {
					obj: state,
					name: stateName,
					type: packageName,
					memberIndex: index,
					members: []
				};
			}
		}

		for (index => inspectorObject in currentStateObjects) {
			updateObjectMembers(index, inspectorObject);
		}
	}

	function updateObjectMembers(index:Int, inspectorObject:InspectorObject, fromGroup:Bool = false) {
		var objMembers:Array<Dynamic> = inspectorObject.obj.members;
		#if foxlite
		if (inspectorObject.obj is FoxScene) {
			objMembers = inspectorObject.obj.foxGroup.members;
		}
		#end
		if (objMembers == null) {
			return;
		}

		//sort and remove if needed
		var membersToRemove:Array<InspectorObject> = [];
		for (member in inspectorObject.members) {
			var currentIndex:Int = objMembers.indexOf(member.obj);
			if (currentIndex == -1) {
				membersToRemove.push(member);
			}
			member.memberIndex = currentIndex;
		}
		for (m in membersToRemove) inspectorObject.members.remove(m);
		inspectorObject.members.sort(function(a, b) {
           if(a.memberIndex < b.memberIndex) return -1;
           else if(a.memberIndex > b.memberIndex) return 1;
           else return 0;
        });

		//we have new members to add
		if (inspectorObject.members.length != objMembers.length) {
			var newList:Array<InspectorObject> = [];
			var oldListIndex:Int = 0;
			for (i in 0...objMembers.length) {
				if (inspectorObject.members[oldListIndex] == null || inspectorObject.members[oldListIndex].memberIndex != i || inspectorObject.members[oldListIndex].obj != objMembers[i]) {
					var member:Dynamic = objMembers[i];
					var memberPackage = hscript.getFieldTypeName(objMembers[i]);
					var memberPackageSplit = memberPackage.split(".");
					var memberType = memberPackageSplit[memberPackageSplit.length-1];
					var memberName:String = fromGroup ? inspectorObject.name + ".members[" + i + "]" : figureOutObjectName(inspectorObject.type, inspectorObject.obj, member);
					var newObj = {
						obj: objMembers[i],
						name: memberName,
						type: memberType,
						memberIndex: i,
						members: [],
						groupParent: fromGroup ? inspectorObject : null
					};
					newList.push(newObj);
					if (member is FlxTypedGroup || member is FlxTypedSpriteGroup #if foxlite || member is FoxScene || member is FoxTypedGroup || member is FoxObjectGroup #end) {
						updateObjectMembers(i, newObj, true);
					}
				} else {
					newList.push(inspectorObject.members[oldListIndex]);
					oldListIndex++;
				}
			}
			inspectorObject.members = newList;
		}
	}

	public function displayUI() {
		
		updateObjects();

		if (ImGui.begin("Inspector")) {
			for (index => member in currentStateObjects) {
				var nodeID = member.name + index;
				var flags = ImGuiTreeNodeFlags.DefaultOpen;
				if (member.obj == selectedObject) flags |= ImGuiTreeNodeFlags.Selected;
				if (ImGui.treeNodeEx(nodeID, flags, member.name + " (" + member.type + ")")) {
					if (ImGui.isItemClicked()) {
						selectObject(member.obj);
					}
					if (member.members.length > 0) {
						generateTreeForMembers(nodeID, member);
					}
					ImGui.treePop();
				}
			}
		}
		ImGui.end();

		if (selectedObject != null) {
			selectedObjectValidThisFrame = false;
			for (member in currentStateObjects) {
				if (member.obj == selectedObject) {
					selectedObjectValidThisFrame = true;
					selectedObjectData = member;
					break;
				}
				checkForSelectedObjectThisFrame(member);
			}

			if (selectedObjectValidThisFrame) {
				showObjectProperties();
			} else {
				selectedObject = null;
				selectedObjectData = null;
			}
		}
	}

	function checkForSelectedObjectThisFrame(object:InspectorObject) {
		if (selectedObjectValidThisFrame) return;
		for (member in object.members) {
			if (member.obj == selectedObject) {
				selectedObjectValidThisFrame = true;
				selectedObjectData = member;
				return;
			}
			if (member.members.length > 0) {
				checkForSelectedObjectThisFrame(member);
			}
		}
	}

	function generateTreeForMembers(id:String, object:InspectorObject) {
		for (index => member in object.members) {
			var valid = member.obj != null;
			var nodeID = id + object.name + index;
			var flags = ImGuiTreeNodeFlags.None;
			if (member.members.length == 0) flags |= ImGuiTreeNodeFlags.Leaf;
			if (valid && member.obj == selectedObject) flags |= ImGuiTreeNodeFlags.Selected;
			if (ImGui.treeNodeEx(nodeID, flags, member.name + (valid ? " (" + member.type + ")" : ""))) {
				if (valid && ImGui.isItemClicked()) {
					selectObject(member.obj);
				}
				if (valid && member.members.length > 0) {
					generateTreeForMembers(nodeID, member);
				}
				ImGui.treePop();
			}
		}
	}

	function selectObject(obj:Dynamic) {
		if (selectedObject != obj) {
			selectedObject = obj;
			justChangedObject = true;
		}
	}

	public function figureOutObjectName(packageName:String, parent:Dynamic, object:FlxBasic) {
		if (object == null) return "Null Member";
		if (!cachedInstanceFields.exists(packageName)) {
			cachedInstanceFields.set(packageName, Type.getInstanceFields(Type.getClass(parent)));
		}
		var instanceFields:Array<String> = cachedInstanceFields.get(packageName);
		var uselessFields:Array<String> = [];
		for (field in instanceFields) {
			if (field == "members") {
				uselessFields.push(field);
				continue;
			}

			var fieldObj:Dynamic = Reflect.getProperty(parent, field);
			if (fieldObj != null) {
				if (fieldObj is FlxBasic) {
					if (object == fieldObj) {
						return field;
					} else if (fieldObj is Stage) {
						var stage:Stage = cast fieldObj;
						for (name => stageObj in stage.stageSprites) {
							if (object == stageObj) return name;
						}
						for (name => posObj in stage.characterPoses) {
							if (object == posObj) return name;
						}
					}
				} else if (fieldObj is Array) {
					var arr:Array<Dynamic> = cast fieldObj;
					var firstMember = arr[0];
					if (firstMember != null && firstMember is FlxBasic) {
						for (index => arrayObj in arr) {
							if (object == arrayObj) {
								return field + "[" + index + "]";
							}
						}
					}
				} else {
					uselessFields.push(field);
				}
			}
		}
		if (uselessFields.length > 0) { //these aren't flxbasic
			for (field in uselessFields) {
				instanceFields.remove(field);
			}
			cachedInstanceFields.set(packageName, instanceFields);
		}

		var scriptPacksToCheck:Array<ScriptPack> = [];
		if (parent is MusicBeatState) {
			var state:MusicBeatState = cast parent;
			scriptPacksToCheck.push(state.stateScripts);
		}
		if (parent is PlayState) {
			var playstate:PlayState = cast parent;
			for (strumLineIndex => strumLine in playstate.strumLines.members) {
				for (charIndex => char in strumLine.characters) {
					if (object == char) {
						return "strumLines[" + strumLineIndex + "].characters[" + charIndex + "] (" + char.curCharacter + ")";
					}
				}
			}
			scriptPacksToCheck.push(playstate.scripts);
		}
		
		for (pack in scriptPacksToCheck) {
			
			for (script in pack.scripts) {
				if (script is HScript) {
					var hscript:HScript = cast script;
					for (name => scriptObj in hscript.interp.variables) {
						if (scriptObj is FlxBasic) {
							if (scriptObj == object) return name;
						} else if (scriptObj is Array) {
							var arr:Array<Dynamic> = cast scriptObj;
							var firstMember = arr[0];
							if (firstMember != null && firstMember is FlxBasic) {
								for (index => arrayObj in arr) {
									if (object == arrayObj) {
										return name + "[" + index + "]";
									}
								}
							}
						}
					}
				}
			}
		}

		return "Unknown" + object.ID;
	}

	var justChangedObject:Bool = false;
	var boolPool:ImGuiPtrPool<ImGuiBoolPtr> = new ImGuiPtrPool<ImGuiBoolPtr>(function() {return new ImGuiBoolPtr(false);});
	var floatPool:ImGuiPtrPool<ImGuiFloatPtr> = new ImGuiPtrPool<ImGuiFloatPtr>(function() {return new ImGuiFloatPtr(0.0);});
	var intPool:ImGuiPtrPool<ImGuiIntPtr> = new ImGuiPtrPool<ImGuiIntPtr>(function() {return new ImGuiIntPtr(0);});
	var float4Pool:ImGuiPtrPool<ImGuiFloat4Ptr> = new ImGuiPtrPool<ImGuiFloat4Ptr>(function() {return new ImGuiFloat4Ptr(0, 0, 0, 0);});
	var stringPool:ImGuiPtrPool<ImGuiStringPtr> = new ImGuiPtrPool<ImGuiStringPtr>(function() {return new ImGuiStringPtr("");});
	
	var mainImageViewer:ImGuiImageViewer = new ImGuiImageViewer();
	var imageViewerMap:Map<Int, ImGuiImageViewer> = [];

	inline function dragFloatField(name:String, field:String, object:Dynamic, speed:Float = 1.0, min:Float = 0.0, max:Float = 0.0, format:String = "%.3f", flags:ImGuiSliderFlags = 0) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);

		var wid = ImGui.getContentRegionAvail().x;
		ImGui.setNextItemWidth(wid);

		var f = floatPool.get();
		f.value = Reflect.getProperty(object, field);
		if (ImGui.dragFloat("##" + name + field, f, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field, f.value);
			didChange = true;
		}
		return didChange;
	}
	inline function dragFloat2Field(name:String, field:String, field2:String, object:Dynamic, speed:Float = 1.0, min:Float = 0.0, max:Float = 0.0, format:String = "%.3f", flags:ImGuiSliderFlags = 0) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var wid = ImGui.getContentRegionAvail().x / 2;
		ImGui.setNextItemWidth(wid);

		var f = floatPool.get();
		f.value = Reflect.getProperty(object, field);
		if (ImGui.dragFloat("##" + name + field, f, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field, f.value);
			didChange = true;
		}

		ImGui.sameLine();
		ImGui.setNextItemWidth(wid);

		var f2 = floatPool.get();
		f2.value = Reflect.getProperty(object, field2);
		if (ImGui.dragFloat("##" + name + field2, f2, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field2, f2.value);
			didChange = true;
		}
		return didChange;
	}
	inline function dragFloat3Field(name:String, field:String, field2:String, field3:String, object:Dynamic, speed:Float = 1.0, min:Float = 0.0, max:Float = 0.0, format:String = "%.3f", flags:ImGuiSliderFlags = 0) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var wid = ImGui.getContentRegionAvail().x / 3;
		ImGui.setNextItemWidth(wid);

		var f = floatPool.get();
		f.value = Reflect.getProperty(object, field);
		if (ImGui.dragFloat("##" + name + field, f, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field, f.value);
			didChange = true;
		}

		ImGui.sameLine();
		ImGui.setNextItemWidth(wid);

		var f2 = floatPool.get();
		f2.value = Reflect.getProperty(object, field2);
		if (ImGui.dragFloat("##" + name + field2, f2, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field2, f2.value);
			didChange = true;
		}

		ImGui.sameLine();
		ImGui.setNextItemWidth(wid);

		var f3 = floatPool.get();
		f3.value = Reflect.getProperty(object, field3);
		if (ImGui.dragFloat("##" + name + field3, f3, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field3, f3.value);
			didChange = true;
		}
		return didChange;
	}
	inline function sliderFloatField(name:String, field:String, object:Dynamic, min:Float, max:Float, format:String = "%.3f", flags:ImGuiSliderFlags = 0) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var wid = ImGui.getContentRegionAvail().x;
		ImGui.setNextItemWidth(wid);

		var f = floatPool.get();
		f.value = Reflect.getProperty(object, field);
		if (ImGui.sliderFloat("##" + name + field, f, min, max, format, flags)) {
			Reflect.setProperty(object, field, f.value);
			didChange = true;
		}
		return didChange;
	}
	inline function dragIntField(name:String, field:String, object:Dynamic, speed:Float = 1.0, min:Int = 0, max:Int = 0, format:String = "%d", flags:ImGuiSliderFlags = 0) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var wid = ImGui.getContentRegionAvail().x;
		ImGui.setNextItemWidth(wid);

		var i = intPool.get();
		i.value = Reflect.getProperty(object, field);
		if (ImGui.dragInt("##" + name + field, i, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field, i.value);
			didChange = true;
		}
		return didChange;
	}
	inline function checkboxField(name:String, field:String, object:Dynamic) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var b = boolPool.get(); b.value = Reflect.getProperty(object, field); 
		if (ImGui.checkbox("##" + name + field, b)) {
			Reflect.setProperty(object, field, b.value);
			didChange = true;
		}
		return didChange;
	}
	inline function textField(name:String, text:String) {
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		ImGui.text(text);
	}
	inline function colorField(name:String, field:String, object:Dynamic, flags:ImGuiColorEditFlags = 0) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var wid = ImGui.getContentRegionAvail().x;
		ImGui.setNextItemWidth(wid);

		var color:FlxColor = Reflect.getProperty(object, field);
		var float4 = float4Pool.get();
		float4.values[0] = color.redFloat;
		float4.values[1] = color.greenFloat;
		float4.values[2] = color.blueFloat;
		float4.values[3] = color.alphaFloat;
		if (ImGui.colorEdit4("##" + name + field, float4, flags)) {
			Reflect.setProperty(object, field, FlxColor.fromRGBFloat(float4.values[0], float4.values[1], float4.values[2], float4.values[3]));
			didChange = true;
		}
		return didChange;
	}
	inline function inputTextField(name:String, field:String, object:Dynamic, flags:ImGuiInputTextFlags = 0) {

		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);

		var wid = ImGui.getContentRegionAvail().x;
		ImGui.setNextItemWidth(wid);

		var s = stringPool.get();
		s.value = Reflect.getProperty(object, field);
		if (ImGui.inputText("##" + name + field, s, flags)) {
			Reflect.setProperty(object, field, s.value);
		}
	}
	inline function inputTextFieldMultiline(name:String, field:String, object:Dynamic, width:Float, height:Float, flags:ImGuiInputTextFlags = 0) {
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var s = stringPool.get();
		s.value = Reflect.getProperty(object, field);
		if (ImGui.inputTextMultiline("##" + name + field, s, width, height, flags)) {
			Reflect.setProperty(object, field, s.value);
		}
	}
	inline function enumFieldString(name:String, field:String, object:Dynamic, list:Array<String>) { //not working
		var index = intPool.get();
		index.value = list.indexOf(Std.string(Reflect.getProperty(object, field)));
		if (ImGui.combo(name + "##" + field, index, list)) {
			Reflect.setProperty(object, field, list[index.value]);
		}
	}
	inline function enumAbstractField(name:String, field:String, object:Dynamic, type:String) {

		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);

		var t = Type.resolveClass(type + "_HSC");
		if (t != null) {
			var wid = ImGui.getContentRegionAvail().x;
			ImGui.setNextItemWidth(wid);

			var curValue = Reflect.getProperty(object, field);
			var index = intPool.get();

			var fields = Type.getClassFields(t);
			var filteredFields:Array<String> = [];
			for (f in fields) {
				if (!f.startsWith("from") && !f.startsWith("to")) filteredFields.push(f);
			}
			index.value = -1;
			for (i => f in filteredFields) {
				if (Reflect.getProperty(t, f) == curValue) index.value = i;
			}

			if (ImGui.combo("##" + name + field, index, filteredFields)) {
				Reflect.setProperty(object, field, Reflect.getProperty(t, filteredFields[index.value]));
			}

		}
	}

	function showObjectProperties() {

		boolPool.reset();
		floatPool.reset();
		intPool.reset();
		float4Pool.reset();
		stringPool.reset();

		if (justChangedObject) {
			mainImageViewer.viewReset = true;
			imageViewerMap.clear();
			justChangedObject = false;
		}

		if (ImGui.begin("Object Properties")) {
			ImGui.text(selectedObjectData.name + " - " + selectedObjectData.type);

			var basic:FlxBasic = selectedObject is FlxBasic ? cast selectedObject : null;
			if (basic != null) {
				showFlxBasicProps(basic);
				//TODO: script stuff here
			}
			#if foxlite
			var foxbasic:FoxBasic = selectedObject is FoxBasic ? cast selectedObject : null;
			if (foxbasic != null) {
				showFoxBasicProps(foxbasic);
			}
			#end
			
		}
		ImGui.end();
	}

	function showFlxBasicProps(basic:FlxBasic) {
		var object:FlxObject = selectedObject is FlxObject ? cast selectedObject : null;
		var sprite:FlxSprite = selectedObject is FlxSprite ? cast selectedObject : null;
		var text:FlxText = selectedObject is FlxText ? cast selectedObject : null;
		var funkinSprite:FunkinSprite = selectedObject is FunkinSprite ? cast selectedObject : null;
		var funkinText:FunkinText = selectedObject is FunkinText ? cast selectedObject : null;

		var tableFlags = ImGuiTableFlags.SizingStretchSame | ImGuiTableFlags.Resizable | ImGuiTableFlags.BordersOuter | ImGuiTableFlags.BordersV | ImGuiTableFlags.RowBg;

		if (object != null) {
			showObjectGizmo(object);
			if (ImGui.collapsingHeader("Transform")) {
				if (ImGui.beginTable("Transform##1", 2, tableFlags))
				{
					dragFloat2Field("Position", "x", "y", object);
					dragFloat2Field("Width/Height", "width", "height", object);
					if (sprite != null) {
						dragFloat2Field("Scale", "x", "y", sprite.scale, 0.05);
						dragFloat2Field("Origin", "x", "y", sprite.origin, 0.1);
						dragFloat2Field("Offset", "x", "y", sprite.offset);
					}
					dragFloatField("Angle", "angle", object);
					dragFloat2Field("Scroll Factor", "x", "y", object.scrollFactor, 0.05);
					if (funkinSprite != null || funkinText != null) {
						dragFloatField("Zoom Factor", "zoomFactor", object, 0.05);
						checkboxField("Enabled", "zoomFactorEnabled", object);
						dragFloatField("Angle Factor", "angleFactor", object, 0.05);
						checkboxField("Enabled", "angleFactorEnabled", object);

						dragFloat2Field("Skew", "x", "y", funkinSprite != null ? funkinSprite.skew : funkinText.skew, 0.05);
					}	

					ImGui.endTable();
				}
			}
			if (sprite != null && ImGui.collapsingHeader("Graphics")) {

				if (sprite.graphic != null) {
					ImGui.text("Key: " + sprite.graphic.key);
					var wid = ImGui.getContentRegionAvail().x;
					if (sprite.graphic.bitmap != null) {
						mainImageViewer.drawCanvas(wid, 300, ImTextureID.fromBitmapData(sprite.graphic.bitmap), sprite.graphic.width, sprite.graphic.height);
					}
				}

				if (ImGui.beginTable("Graphics##1", 2, tableFlags))
				{
					colorField("Color", "color", sprite);
					sliderFloatField("Alpha", "alpha", sprite, 0, 1);

					checkboxField("Flip X", "flipX", sprite);
					checkboxField("Flip Y", "flipY", sprite);
					checkboxField("Antialiasing", "antialiasing", sprite);

					enumAbstractField("Blend Mode", "blend", sprite, "openfl.display.BlendMode");

					ImGui.endTable();
				}
				//final blendModes:Array<String> = ["add", "alpha", "darken", "difference", "erase", "hardlight", "invert", "layer", "lighten", "multiply", "normal", "overlay", "screen", "shader", "subtract", 
					//"colordodge", "colorburn", "softlight", "exclusion", "hue", "saturation", "color", "luminosity"];
				//enumFieldString("Blend Mode", "blend", sprite, blendModes);
			}
			if (sprite != null && ImGui.collapsingHeader("Animation")) {

			}
			if (ImGui.collapsingHeader("Physics")) {
				if (ImGui.beginTable("Physics##1", 2, tableFlags))
				{
					checkboxField("Moves", "moves", object);
					checkboxField("Immovable", "immovable", object);
					checkboxField("Solid", "solid", object);

					dragFloat2Field("Velocity", "x", "y", object.velocity);
					dragFloat2Field("Acceleration", "x", "y", object.acceleration);
					dragFloat2Field("Drag", "x", "y", object.drag);
					dragFloatField("Mass", "mass", object);
					dragFloatField("Elasticity", "elasticity", object);
					dragFloatField("Angular Velocity", "angularVelocity", object);
					dragFloatField("Angular Acceleration", "angularAcceleration", object);
					dragFloatField("Angular Drag", "angularDrag", object);
					dragFloat2Field("Max Velocity", "x", "y", object.maxVelocity);
					dragFloatField("Max Angular", "maxAngular", object);
					ImGui.endTable();
				}
			}
			if (text != null && ImGui.collapsingHeader("Text")) {
				if (ImGui.beginTable("Text##1", 2, tableFlags))
				{
					inputTextFieldMultiline("Text", "text", text, 400, 200);
					dragIntField("Size", "size", text);
					inputTextField("Font", "font", text);
					dragFloat2Field("Field Width/Height", "fieldWidth", "fieldHeight", text);
					enumAbstractField("Alignment", "alignment", text, "flixel.text.FlxTextAlign");
					dragFloatField("Letter Spacing", "letterSpacing", text);

					colorField("Border Color", "borderColor", text);

					{
						ImGui.tableNextRow();
						ImGui.tableSetColumnIndex(0);
						ImGui.text("Border Style");
						ImGui.tableSetColumnIndex(1);
						var wid = ImGui.getContentRegionAvail().x;
						ImGui.setNextItemWidth(wid);

						var index = intPool.get();
						var list = ["NONE", "SHADOW", "SHADOW_XY", "OUTLINE", "OUTLINE_FAST"];
						switch(text.borderStyle) { //not that easy to automate due to args on SHADOW_XY
							case NONE:
								index.value = 0;
							case SHADOW:
								index.value = 1;
							case SHADOW_XY(offsetX, offsetY):
								index.value = 2;
							case OUTLINE:
								index.value = 3;
							case OUTLINE_FAST:
								index.value = 4;
						}			
						if (ImGui.combo("##Border StyleborderStyle", index, list)) {
							switch(index.value) {
								case 0:
									text.borderStyle = NONE;
								case 1:
									text.borderStyle = SHADOW;
								case 2:
									text.borderStyle = SHADOW_XY(0, 0);
								case 3:
									text.borderStyle = OUTLINE;
								case 4:
									text.borderStyle = OUTLINE_FAST;
							}
						}

						switch(text.borderStyle) {
							case SHADOW_XY(offsetX, offsetY):
								//todo
							default:
						}	
					}
					dragFloatField("Border Size", "borderSize", text);
					dragFloatField("Border Quality", "borderQuality", text);

					checkboxField("Bold", "bold", text);
					checkboxField("Underline", "underline", text);
					checkboxField("Italic", "italic", text);
					checkboxField("Word Wrap", "wordWrap", text);
					checkboxField("Auto Size", "autoSize", text);
					ImGui.endTable();
				}				
			}
		}

		if (ImGui.collapsingHeader("Basic")) {
			if (ImGui.beginTable("Basic##1", 2, tableFlags))
			{
				checkboxField("Active", "active", basic);
				checkboxField("Visible", "visible", basic);
				checkboxField("Alive", "alive", basic);
				checkboxField("Exists", "exists", basic);
				ImGui.endTable();
			}
		}
	}

	#if foxlite
	function showFoxBasicProps(basic:FoxBasic) {
		var object:FoxObject = selectedObject is FoxObject ? cast selectedObject : null;
		var model:FoxModel = selectedObject is FoxModel ? cast selectedObject : null;

		var tableFlags = ImGuiTableFlags.SizingStretchSame | ImGuiTableFlags.Resizable | ImGuiTableFlags.BordersOuter | ImGuiTableFlags.BordersV | ImGuiTableFlags.RowBg;

		if (object != null) {
			ImGui.separator();
			if (ImGui.collapsingHeader("Transform")) {
				if (ImGui.beginTable("Transform##1", 2, tableFlags))
				{
					var dirty = false;
					if (dragFloat3Field("Position", "x", "y", "z", object.position, 0.05)) dirty = true;
					if (dragFloat3Field("Rotation", "angleX", "angleY", "angleZ", object)) dirty = true;
					if (dragFloat3Field("Scale", "x", "y", "z", object.scale, 0.05)) dirty = true;
					if (dirty) {
						object.update(0.0); //force update transform
					}
					ImGui.endTable();
				}
			}

			if (model != null && ImGui.collapsingHeader("Graphics")) {

				if (ImGui.beginTable("Model##1", 2, tableFlags))
				{
					checkboxField("Frustrum Culling", "frustumCulling", model);
					checkboxField("Cast Shadows", "castShadows", model);
					checkboxField("Cast Colored Shadows", "castColoredShadows", model);
					ImGui.endTable();
				}

				ImGui.separator();
				
				for (i => mesh in model.meshes) {
					var nodeID = "mesh" + i;
					if (ImGui.treeNode(nodeID, mesh.assetsKey != null ? mesh.assetsKey : "Mesh " + i)) {
						ImGui.pushIDFromInt(i);
						if (ImGui.beginTable("MeshTable" + i, 2, tableFlags))
						{
							textField("Key", mesh.assetsKey);
							textField("Is Copy", mesh.__isCopy ? "True" : "False");
							@:privateAccess {
								if (mesh.vertexBuffer != null) textField("Vertex Buffer", "Num: " + mesh.vertexBuffer.__numVertices + ", Stride: " + mesh.vertexBuffer.__stride + ", Size: " + mesh.vertexBuffer.__memoryUsage);
								if (mesh.uvBuffer != null) textField("UV Buffer", "Num: " + mesh.uvBuffer.__numVertices + ", Stride: " + mesh.uvBuffer.__stride + ", Size: " + mesh.uvBuffer.__memoryUsage);
								if (mesh.indexBuffer != null) textField("Index Buffer", "Num: " + mesh.indexBuffer.__numIndices + ", Size: " + mesh.indexBuffer.__memoryUsage);
								if (mesh.normalBuffer != null) textField("Normal Buffer", "Num: " + mesh.normalBuffer.__numVertices + ", Stride: " + mesh.normalBuffer.__stride + ", Size: " + mesh.normalBuffer.__memoryUsage);
								if (mesh.tangentBuffer != null) textField("Tangent Buffer", "Num: " + mesh.tangentBuffer.__numVertices + ", Stride: " + mesh.tangentBuffer.__stride + ", Size: " + mesh.tangentBuffer.__memoryUsage);
								if (mesh.colorBuffer != null) textField("Color Buffer", "Num: " + mesh.colorBuffer.__numVertices + ", Stride: " + mesh.colorBuffer.__stride + ", Size: " + mesh.colorBuffer.__memoryUsage);
								if (mesh.boneWeights != null) textField("Bone Weights Buffer", "Num: " + mesh.boneWeights.__numVertices + ", Stride: " + mesh.boneWeights.__stride + ", Size: " + mesh.boneWeights.__memoryUsage);
								if (mesh.colorBuffer != null) textField("Bone Indices Buffer", "Num: " + mesh.boneIndices.__numVertices + ", Stride: " + mesh.boneIndices.__stride + ", Size: " + mesh.boneIndices.__memoryUsage);
							}
							ImGui.endTable();
						}
						
						if (mesh.material != null) {
							ImGui.separatorText("Material");
							if (ImGui.beginTable("MaterialTable" + i, 2, tableFlags))
							{
								textField("Name", mesh.material.name);
								textField("Key", mesh.material.assetsKey);
								checkboxField("Depth Test", "depthTest", mesh.material);
								enumAbstractField("Depth Func", "depthFunc", mesh.material, "foxlite.material.FoxDepthCompareMode");
								checkboxField("Depth Write", "depthWrite", mesh.material);
								checkboxField("Color Write", "colorWrite", mesh.material);
								enumAbstractField("Culling", "culling", mesh.material, "foxlite.material.FoxTriangleFace");
								enumAbstractField("Shadow Culling", "shadowCulling", mesh.material, "foxlite.material.FoxTriangleFace");
								enumAbstractField("Blend Mode", "blendMode", mesh.material, "foxlite.material.FoxBlendMode");
								sliderFloatField("Alpha Scissor", "alphaScissor", mesh.material, 0, 1);
								dragIntField("Render Priority", "renderPriority", mesh.material);
								ImGui.endTable();
							}



							if (ImGui.treeNode(nodeID + "textures", "Textures")) {
								for (texName => tex in mesh.material.textures) {
									ImGui.separatorText(texName);
									var wid = ImGui.getContentRegionAvail().x;
									@:privateAccess
									var id:Int = tex.glTexture.__getTexture().id;
									if (id != 0) {
										if (!imageViewerMap.exists(id)) imageViewerMap.set(id, new ImGuiImageViewer());
										imageViewerMap.get(id).drawCanvas(wid, 300, new ImTextureID(id), tex.width, tex.height);
									}
								}
								ImGui.treePop();
							}
							if (ImGui.treeNode(nodeID + "params", "Parameters")) {
								if (ImGui.beginTable("ParamsTable" + i, 2, tableFlags)) {
									for (name => value in mesh.material.params) {
										textField(name, Std.string(value));
									}
									ImGui.endTable();
								}
								ImGui.treePop();
							}						
						}
						ImGui.popID();
						ImGui.treePop();
					}
				}
			}
		}

		if (ImGui.collapsingHeader("Basic")) {
			if (ImGui.beginTable("Basic##1", 2, tableFlags))
			{
				textField("Name", basic.name);
				checkboxField("Active", "active", basic);
				checkboxField("Visible", "visible", basic);
				ImGui.endTable();
			}
		}
		//ImGui.text("Name: " + basic.name);
		//checkbox("Active", "active", basic);
		//ImGui.sameLine();
		//checkbox("Visible", "visible", basic);
	}
	#end

	////////////////////////////////////////////////
	
	inline function transformFlxPointToWindowSpace(point:FlxPoint) {
		if ((ImGuiIO.configFlags & ImGuiConfigFlags.ViewportsEnable) != 0) {
			point.x = (Lib.application.window.x + FlxG.scaleMode.offset.x) + (point.x * FlxG.scaleMode.scale.x);
			point.y = (Lib.application.window.y + FlxG.scaleMode.offset.y) + (point.y * FlxG.scaleMode.scale.y);
		} else {
			point.x = (FlxG.scaleMode.offset.x) + (point.x * FlxG.scaleMode.scale.x);
			point.y = (FlxG.scaleMode.offset.y) + (point.y * FlxG.scaleMode.scale.y);
		}
	}
	inline function transformFlxPointOntoCamera(point:FlxPoint, camera:FlxCamera) {
		point.subtract(camera.viewMarginLeft, camera.viewMarginTop);
		point.x *= camera.zoom;
		point.y *= camera.zoom;
	}

	function prepareObjectCamera(basic:FlxBasic) {
		var parentsList:Array<Dynamic> = [];
		var oldDefaultCamerasList:Array<Array<FlxCamera>> = [];
		
		var parent = selectedObjectData.groupParent;
		while(parent != null) {
			parentsList.insert(0, parent.obj);
			parent = parent.groupParent;
		}

		@:privateAccess
		for (p in parentsList) {
			oldDefaultCamerasList.push(FlxCamera._defaultCameras);
			var group:FlxBasic = cast p;
			if (group._cameras != null) FlxCamera._defaultCameras = group._cameras;
		}

		var camera = basic.getDefaultCamera();

		@:privateAccess
		if (oldDefaultCamerasList.length > 0) FlxCamera._defaultCameras = oldDefaultCamerasList[0]; //no point looping back, just grab first

		return camera;
	}

	function showObjectGizmo(object:FlxObject) {
		var sprite:FlxSprite = cast object;
		var drawList = ImGui.getForegroundDrawList(ImGui.getMainViewport());

		var camera = prepareObjectCamera(object);
		var bounds = object.getScreenPosition(null, camera);
		var position = bounds.clone();
		var origin = bounds.clone();
		if (sprite != null) {
			bounds.subtractPoint(sprite.offset);
			origin.addPoint(sprite.origin);
		}
		transformFlxPointOntoCamera(bounds, camera);
		transformFlxPointToWindowSpace(bounds);
		transformFlxPointOntoCamera(position, camera);
		transformFlxPointToWindowSpace(position);
		transformFlxPointOntoCamera(origin, camera);
		transformFlxPointToWindowSpace(origin);

		if (sprite == null)
		{
			var x = bounds.x;
			var y = bounds.y;
			var right = x + (object.width * camera.zoom);
			var bottom = y + (object.height * camera.zoom);
			/*var minX = Lib.application.window.x + FlxG.scaleMode.offset.x;
			var minY = Lib.application.window.y + FlxG.scaleMode.offset.y;
			var maxX = Lib.application.window.x + FlxG.scaleMode.offset.x + FlxG.scaleMode.gameSize.x;
			var maxY = Lib.application.window.y + FlxG.scaleMode.offset.y + FlxG.scaleMode.gameSize.y;
			
			if (x < minX) x = minX;
			if (y < minY) y = minY;
			if (right > maxX) right = maxX;
			if (bottom > maxY) bottom = maxY;*/
			drawList.addRect([x, y, right, bottom], 0xFFB922F5, 0, 4);
		}
		else
		{
			if (sprite.frame != null) {
				@:privateAccess
				var matrix:FlxMatrix = sprite._matrix;
				//var pointTL = new Point(sprite.frame.x, sprite.frame.frame.y);
				//var pointTR = new Point(sprite.frame.frame.x + sprite.frame.frame.width, sprite.frame.frame.y);
				//var pointBL = new Point(sprite.frame.frame.x, sprite.frame.frame.y + sprite.frame.frame.height);
				//var pointBR = new Point(sprite.frame.frame.x + sprite.frame.frame.width, sprite.frame.frame.y + sprite.frame.frame.height);
				//var pointTL = FlxPoint.get(sprite.frame.offset.x, sprite.frame.offset.y);
				//var pointTR = FlxPoint.get(pointTL.x + sprite.frame.frame.width, pointTL.y);
				//var pointBL = FlxPoint.get(pointTL.x, pointTL.y + sprite.frame.frame.height);
				//var pointBR = FlxPoint.get(pointTL.x + sprite.frame.frame.width, pointTL.y + sprite.frame.frame.height);

				var pointTL = FlxPoint.get(0, 0);
				var pointTR = FlxPoint.get(0 + sprite.frame.frame.width, 0);
				var pointBL = FlxPoint.get(0, 0 + sprite.frame.frame.height);
				var pointBR = FlxPoint.get(0 + sprite.frame.frame.width, 0 + sprite.frame.frame.height);
				
				pointTL = pointTL.transform(matrix);
				pointTR = pointTR.transform(matrix);
				pointBL = pointBL.transform(matrix);
				pointBR = pointBR.transform(matrix);
				transformFlxPointOntoCamera(pointTL, camera);
				transformFlxPointOntoCamera(pointTR, camera);
				transformFlxPointOntoCamera(pointBL, camera);
				transformFlxPointOntoCamera(pointBR, camera);
				transformFlxPointToWindowSpace(pointTL);
				transformFlxPointToWindowSpace(pointTR);
				transformFlxPointToWindowSpace(pointBL);
				transformFlxPointToWindowSpace(pointBR);
				drawList.addQuad([pointTL.x, pointTL.y, pointTR.x, pointTR.y, pointBR.x, pointBR.y, pointBL.x, pointBL.y], 0xFFB922F5, 4);
			}
		}

		drawList.addCircleFilled(position.x, position.y, 5, 0xFFFF0000);
		if (sprite != null) {
			drawList.addCircleFilled(origin.x, origin.y, 5, 0xFF1500FF);
		}
	}
}

//quick class that handles imgui pointers for temp values
class ImGuiPtrPool<T> {
	var members:Array<T> = [];
	var used:Int = 0;
	var constructor:Void->T;
	public function new(constructor:Void->T) {
		this.constructor = constructor;
	}
	public function reset() {
		used = 0;
	}
	public function get():T {
		if (used >= members.length) {
			members.push(constructor());
		}
		var obj = members[used];
		used++;
		return obj;
	}
}

//https://github.com/ocornut/imgui/blob/master/imgui_demo.cpp#L841
class ImGuiImageViewer {
	var gridEnabled:ImGuiBoolPtr = new ImGuiBoolPtr(false);
	public var viewReset:Bool = true;
	var viewOffsetX:Float = 0;
	var viewOffsetY:Float = 0;
	var zoom:ImGuiFloatPtr = new ImGuiFloatPtr(10.0);
	var zoom100:ImGuiFloatPtr = new ImGuiFloatPtr(10.0);
	var zoomMin:Float = 0.1;
	var zoomMax:Float = 10000;

	public function new() {}

	public function drawOptions() {
		ImGui.setNextItemWidth(150);
		zoom100.value = zoom.value * 100;
		if (ImGui.dragFloat("Zoom", zoom100, 5.0, zoomMin * 100.0, zoomMax * 100, "%.0f%%", ImGuiSliderFlags.AlwaysClamp))
			zoom.value = zoom100.value / 100.0;
	}

	public function drawCanvas(canvas_size_x:Float, canvas_size_y:Float, image_tex_ref:ImTextureID, image_w:Int, image_h:Int) {
		var drawList = ImGui.getWindowDrawList();
		ImGui.invisibleButton("##Canvas", canvas_size_x, canvas_size_y);
		var canvas_min = ImGui.getItemRectMin();
		var canvas_max = ImGui.getItemRectMax();

		if (viewReset) {
			var xZoom = canvas_size_x / image_w;
			var yZoom = canvas_size_y / image_h;
			zoom.value = (image_w > image_h ? xZoom : yZoom);
			viewOffsetX = (canvas_size_x * 0.5 / xZoom) - 0.5;
			viewOffsetY = (canvas_size_y * 0.5 / yZoom) - 0.5;
		}
		viewReset = false;

		if (ImGui.setItemKeyOwner(ImGuiKey.MouseWheelY)) {
			if (ImGuiIO.mouseWheel != 0.0) {
				zoom.value = FlxMath.bound(zoom.value * (1.0 + ImGuiIO.mouseWheel * 0.10), zoomMin, zoomMax);
			}
		}
		var zoomValue = zoom.value;
		if (ImGui.isItemActive() && ImGui.isMouseDragging(0)) {
			viewOffsetX -= ImGuiIO.mouseDeltaX / zoomValue;
			viewOffsetY -= ImGuiIO.mouseDeltaY / zoomValue;
		}

		var minX:Float = Std.int((canvas_min.x - (viewOffsetX * zoomValue)) + (canvas_size_x * 0.5));
		var minY:Float = Std.int((canvas_min.y - (viewOffsetY * zoomValue)) + (canvas_size_y * 0.5));
		var maxX:Float = Std.int(minX + image_w * zoomValue);
		var maxY:Float = Std.int(minY + image_h * zoomValue);
		drawList.addRect([canvas_min.x - 1.0, canvas_min.y - 1.0, canvas_max.x + 1.0, canvas_max.y + 1.0], 0xFFFFFFFF);
		drawList.pushClipRect(canvas_min.x, canvas_min.y, canvas_max.x, canvas_max.y, true);
		drawList.addRectFilled([minX, minY, maxX, maxY], 0xFF646464);
		drawList.addImage(image_tex_ref, [minX, minY, maxX, maxY]);

		if (gridEnabled.value && zoomValue > 6.0)
		{
			var step:Float = zoomValue;
			for (px in Std.int((canvas_min.x - minX) / step)...Std.int((canvas_max.x - minX) / step)) {
				drawList.addLineV(minX + px * step, canvas_min.y, canvas_max.y, 0x64FFFFFF, 1.0);
			}
			for (py in Std.int((canvas_min.y - minY) / step)...Std.int((canvas_max.y - minY) / step)) {
				drawList.addLineH(canvas_min.x, canvas_max.x, minY + py * step, 0x64FFFFFF, 1.0);
			}
		}
		drawList.popClipRect();
	}

	#end
}