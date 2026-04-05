--// > HeadService.lua < //--
--// ! Made by BloodLight (@Heavenly_Strings)
--// ? Converts the face to HD
--// ? this does require alot more comments tho ngl..
--!optimize 2
--!native
local HeadService = {}

--// > Services < //--
--// ? all services used in this service
local Selection = game:GetService("Selection")

--// > Resources < //--
--// ? all the modules and assets used in this service
local NotificationService = require(script.Parent.NotificationService)
local Preferences --// ? preferences
local faceScale = Vector3.new(1.25, 1.25, 1.25) --// ? scale 

--// > Helpers < //--
--// ? helpers used in the service
function HeadService.Init(prefsTable) Preferences = prefsTable end

--// > Main < //--
--// ? the main part of this service
function HeadService.ConvertHead()
	if not Preferences then error("{BloodifyPlugin} [!] // > HeadService not initialized! No Preferences ModuleScript. Did you modify the source code and remove it?") return end

	local startTime = os.clock() --// ? start time of conversion process
	local selected = Selection:Get() --// ? get current selection

	if #selected == 0 then
		return NotificationService.Notify("No selection found! Did you do this to test?", false, "HeadService", 3) --// ? no selection found
	end

	local successCount = 0 --// ? count of successful conversions
	local failReasons = {} --// ? table for fail reasons
	
	--// ? check if the selection is a model
	for _, model in ipairs(selected) do
		if not model:IsA("Model") then table.insert(failReasons, model.Name .. ": Not a model!") continue end --// ? fail reason

		local head = model:FindFirstChild("Head") --// ? find head in model
		if not head then table.insert(failReasons, model.Name .. ": No Head found!") continue end --// ? fail reason

		local currentFace = head:FindFirstChild("face") or head:FindFirstChild("Face") or head:FindFirstChildOfClass("Decal") --// ? face decal

		if not currentFace then table.insert(failReasons, ("["..model.Name.."]: " .. "No face found!")) continue --// ? not found
		elseif not currentFace:IsA("Decal") then table.insert(failReasons, ("["..model.Name.."]: " .. "Face not a Decal!")) continue --// ? not a decal
		end

		local facePart = Instance.new("Part") --// ? main part
		facePart.Name = Preferences.facePartName or "FacePart" --// ? name
		facePart.Size, facePart.CFrame, facePart.Transparency = head.Size, head.CFrame, 1 --// ? size and cframe
		--// ? collisions
		facePart.CanCollide, facePart.CanQuery, facePart.CanTouch, facePart.AudioCanCollide, facePart.Anchored, facePart.EnableFluidForces = false, false, false, false, false, false

		local weld = Instance.new(if Preferences.useLegacyFaceWeld then "Weld" else "WeldConstraint") --// ? weld
		weld.Name = ("Weld [%s] >> [%s]"):format(head.Name, facePart.Name) --// ? weld name
		weld.Part0, weld.Part1 = head, facePart --// ? weld parts
		weld.Parent = facePart --// ? weld parent

		if weld:IsA("Weld") then weld.C0, weld.C1 = CFrame.new() , facePart.CFrame:ToObjectSpace(head.CFrame) end --// ? if legacy weld, use legacy weld vers of Part0/Part1

		local faceMesh = Instance.new("SpecialMesh") --// ? specialmesh for facePart
		local originalFaceMesh = head:FindFirstChild("SpecialMesh") --// ? original specialmesh of Head
		
		faceMesh.MeshType = Enum.MeshType.Head
		faceMesh.Name = Preferences.faceMeshName or "HeadMesh" --// ? name
		faceMesh.Scale = faceScale --// ? scale of faceMesh
		faceMesh.Parent = facePart

		local mainFace = Instance.new("Decal") --// ? decal that holds the face
		mainFace.Name = Preferences.faceDecalName or "MainFaceDecal" --// ? name
		mainFace.Texture = currentFace.Texture --// ? texture/id of decal
		mainFace.Parent = facePart

		if Preferences.keepOldFace then --// ? HDify feature
			local oldFaceFolder = head:FindFirstChild("OldFace") or Instance.new("Folder")
			if oldFaceFolder.Parent ~= head then
				oldFaceFolder.Name = "OldFace" --// ? name
				oldFaceFolder.Parent = head
			end currentFace.Parent = oldFaceFolder
		else currentFace:Destroy()
		end

		facePart.Parent = head
		successCount += 1 --// ? yay one Head done!!
	end

	local duration = os.clock() - startTime --// ? total time for all Heads converted
	local isSuccess = (successCount > 0) --// ? if there is atleast one Head converted, then it is a success
	local resultMsg = ("Converted %d face(s) in %.2fs (%.1fms)"):format(successCount, duration, duration * 1000)

	if #failReasons > 0 then resultMsg ..= "\nSkipped:\n" .. table.concat(failReasons, "\n") end  --// ? skipped heads/models

	NotificationService.Notify(resultMsg, isSuccess, "HeadService", 6)
	return successCount
end

return HeadService
