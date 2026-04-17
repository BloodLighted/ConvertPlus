--// > AccessoryService.lua < //--
--// ! Made by BloodLight (@Heavenly_Strings)
--// Handles converting, coloring, naming, and welding accessories/hats
--!optimize 2
--!native
--!strict
local AccessoryService = {}

--// > Services < //--
--// ! all services used in this service
local Selection = game:GetService("Selection") --// for getting current selection
local InsertService = game:GetService("InsertService") --// for inserting the meshpart
local ChangeHistoryService = game:GetService("ChangeHistoryService") --// to revert changes

--// > Resources < //--
--// ! all the modules and assets used in this service
local NotificationService = require(script.Parent.NotificationService) --// for notifications
local Preferences: any --// preferences
local sessionCache: {[string]: MeshPart} = {} --// store meshes in current session

--// > Helpers < //--
--// ! helpers used in the service
--// for baking the vertex color onto the color of the MeshPart
local function bakeVertexColor(pColor: Color3, vVector: Vector3): Color3
	return Color3.new(math.clamp(pColor.R * vVector.X, 0, 1), math.clamp(pColor.G * vVector.Y, 0, 1), math.clamp(pColor.B * vVector.Z, 0, 1))
end

function AccessoryService.Init(prefsTable: any) Preferences = prefsTable end --// init

--// > Main < //--
--// the main part of this service
function AccessoryService.ConvertAccessories(): number
	if not Preferences then --// no idea how this would even happen ngl unless it's a custom version of the plugin
		error("{ConvertPlus} [!] // > AccessoryService not initialized! No Preferences ModuleScript. Did you modify the source code and remove it?")
		return 0
	end

	local startTime: number, selected: {Instance} = os.clock(), Selection:Get() --// start time of conversion process, aswell as current selection

	if #selected == 0 then NotificationService.Notify("No selection found! Did you do this to test?", false, "AccessoryService", 3) return 0 end --// no selection found

	local successCount: number, failReasons: {string} = 0, {} --// to count the number of successful conversions, and to store the reasons for failed conversions
	local taskQueue: {any} = {} --// queue of tasks to be performed
	local meshTemplates: {[string]: MeshPart}, uniqueMeshIds: {[string]: number} = {}, {} --// store mesh templates and their unique ids
	local folderCache: {[Instance]: {[string]: Folder}} = {} --// store folders for reuse
	local modelsToProcess: {Model}, processedModels: {[Instance]: boolean} = {}, {} --// to store models to process and models that have been processed
	
	--// check if the selection is a model or a folder, if it's a model, add it to the models to process, if it's a folder, add all the models in the folder to process
	for _, obj in ipairs(selected) do
		if obj:IsA("Model") and not processedModels[obj] then --// add to process if model
			processedModels[obj] = true --// add to dictionary
			table.insert(modelsToProcess, obj) --// add to process
		elseif obj:IsA("Folder") then
			for _, desc in ipairs(obj:GetDescendants()) do if desc:IsA("Model") then --// add all descendants of folder to process if folder
					processedModels[desc] = true --// add to dictionary
					table.insert(modelsToProcess, desc) --// add to process
				end
			end
		else table.insert(failReasons, "[" .. obj.Name .. "]: Not a model/folder!") end --// fail reason
	end
	
	--// check if the model has accessories; if it does, add them to the task queue
	for _, model in ipairs(modelsToProcess) do
		local foundInModel = false
		for _, acc in ipairs(model:GetDescendants()) do
			if acc:IsA("Accessory") or acc:IsA("Hat") then --// if accessory
				local handle = acc:FindFirstChild("Handle") or acc:FindFirstChildOfClass("BasePart") --// handle of accessory
				local mesh = handle and handle:FindFirstChildOfClass("SpecialMesh") --// mesh of accessory

				if handle and mesh and mesh.MeshId ~= "" then
					table.insert(taskQueue, {Acc = acc, Handle = handle, Mesh = mesh, Model = model}) --// insert into queue
					if not uniqueMeshIds[mesh.MeshId] then uniqueMeshIds[mesh.MeshId] = 0 end
					foundInModel = true
				else table.insert(failReasons, "[" .. acc.Name .. "]: Missing Mesh Data!") end --// no mesh data
			end
		end

		if not foundInModel and #selected == 1 then table.insert(failReasons, "[" .. model.Name .. "]: No valid accessories found!") end --// no accessories
	end

	local toDownload: {string} = {}

	for meshId, _ in pairs(uniqueMeshIds) do
		if sessionCache[meshId] then meshTemplates[meshId] = sessionCache[meshId] else table.insert(toDownload, meshId) end
	end
	
	--// create MeshPart and count it as a completed download
	if #toDownload > 0 then
		local completedDownloads = 0
		local masterThread = coroutine.running() --// main thread
		local renderFidelity = Preferences.accessoryRenderFidelity or Enum.RenderFidelity.Automatic
		local collisionFidelity = Preferences.accessoryCollisionFidelity or Enum.CollisionFidelity.Hull
		for _, meshId in ipairs(toDownload) do --// meshes to download
			task.spawn(function()
				local success, part = pcall(function()
					return InsertService:CreateMeshPartAsync(meshId, collisionFidelity, renderFidelity) end) --// creates meshpart

				if success and part then 
					for _, child in part:GetChildren() do
						if child:IsA("SpecialMesh") or child:IsA("Weld") or child:IsA("ManualWeld") then child.Parent = nil end --// parent to nil
					end
					sessionCache[meshId] = part meshTemplates[meshId] = part end
				completedDownloads += 1 --// download completed
				if completedDownloads >= #toDownload then task.defer(masterThread) end --// all have been downloaded
			end)
		end coroutine.yield() --// yield until all meshes have been downloaded
	end
	
	local recording = ChangeHistoryService:TryBeginRecording("ConvertAccessories")
	if not recording then return 0 end
	
	local prefCanQuery, prefCanTouch = Preferences.accessoryCanQuery or false, Preferences.accessoryCanTouch or false
	local prefSoundCollision = Preferences.accessorySoundCollision or false
	local prefFluidForces = Preferences.accessoryFluidForces or false
	local prefix = Preferences.accessoryNamePrefix or "[Accessory]"

	for _, data in ipairs(taskQueue) do --// start main process
		local acc: Accessory, handle: BasePart, mesh: SpecialMesh = data.Acc, data.Handle, data.Mesh --// accessory data
		local template = meshTemplates[mesh.MeshId]

		if not template then table.insert(failReasons, "[" .. acc.Name .. "]: Mesh download failed!") continue end --// fail reason

		local weldbutnotreally = handle:FindFirstChildOfClass("Weld") or handle:FindFirstChild("AccessoryWeld")
		local limb: BasePart?
		if weldbutnotreally and (weldbutnotreally:IsA("Weld") or weldbutnotreally:IsA("ManualWeld")) then
			local weld = weldbutnotreally :: Weld --// just so strict shuts up
			limb = (weld.Part0 == handle and weld.Part1 or weld.Part0) :: BasePart --// limb of accessory
		end

		if not limb or not limb:IsA("BasePart") then table.insert(failReasons, "[" .. acc.Name .. "]: No limb/basepart found to weld to!") continue end --// fail reason

		local targetParent = Preferences.useLegacyAccessoryParenting and data.Model or limb
		local folderName = Preferences.useLegacyAccessoryParenting and "Accessories/Hats" or (limb.Name .. " | Accessories")
		local parentCache = folderCache[targetParent]
		if not parentCache then parentCache = {} folderCache[targetParent] = parentCache end
		
		if not folderCache[targetParent] then folderCache[targetParent] = {} end
		
		local folder: Folder --// folder of Accessories
		local cachedFolder = parentCache[folderName]
		if cachedFolder then folder = cachedFolder
		else
	local foundFolder = targetParent:FindFirstChild(folderName)
	if foundFolder and foundFolder:IsA("Folder") then folder = foundFolder
	else
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = targetParent
	end parentCache[folderName] = folder end

		local accessoryPart = template:Clone() --// clone the template
		
		local cleanName = acc.Name:gsub("^[Aa][Cc][Cc][Ee][Ss][Ss][Oo][Rr][Yy]", ""):gsub("[%s%(%)]", "") --// remove original accessory tag if there is one
		accessoryPart.Name = (Preferences.accessoryNamePrefix or "[Accessory]") .. " " .. cleanName
		accessoryPart.Color = bakeVertexColor(handle.Color, mesh.VertexColor) --// bake color
		accessoryPart.Size *= mesh.Scale
		accessoryPart.TextureID, accessoryPart.Material, accessoryPart.CFrame = mesh.TextureId, handle.Material, handle.CFrame --// copy over main properties
		accessoryPart.CanCollide, accessoryPart.CanQuery, accessoryPart.CanTouch, accessoryPart.AudioCanCollide = false, prefCanQuery, prefCanTouch, prefSoundCollision
		accessoryPart.EnableFluidForces = Preferences.accessoryFluidForces or false

		local wc = Instance.new("WeldConstraint") --// weld
		wc.Part0, wc.Part1 = limb, accessoryPart --// welds limb to Accessory
		wc.Name = "Weld [".. limb.Name .."] >> [".. accessoryPart.Name .."]" --// [Head] >> [Accessory]

		if Preferences.useLegacyWeldParenting then local wf: Folder
			local existingWf = folder:FindFirstChild("WeldFolder")

			if existingWf and existingWf:IsA("Folder") then wf = existingWf
			else wf = Instance.new("Folder")
				wf.Name = "WeldFolder"
				wf.Parent = folder
			end wc.Parent = wf
		else wc.Parent = accessoryPart end

		accessoryPart.Parent = folder --// parent new Accessory to folder
		acc.Parent = nil
		successCount += 1 --// one accessory done
	end

	local duration: number = os.clock() - startTime --// total time for all accessories converted
	local isSuccess: boolean = (successCount > 0) --// if there is atleast one accessory converted, then it is a success
	local resultMsg: string = ("Converted %d accessor(y/ies) in %.2fs (%.1fms)"):format(successCount, duration, duration * 1000)

	if #failReasons > 0 then resultMsg ..= "\nSkipped:\n" .. table.concat(failReasons, "\n") end --// skipped accessories/models
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit) --// finish recording
	NotificationService.Notify(resultMsg, isSuccess, "AccessoryService") --// final notification
	return successCount
end
return AccessoryService
