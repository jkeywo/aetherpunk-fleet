extends "res://scripts/screen.gd"


func _ready() -> void:
	super._ready()
	BattleSession.campaign_battle = false
	%NewCampaignButton.pressed.connect(_confirm_new_campaign)
	%ContinueCampaignButton.pressed.connect(_continue_campaign)
	%NewCampaignButton.disabled = ContentStore.saved.is_empty()
	%ContinueCampaignButton.disabled = CampaignStore.run.is_empty()
	var is_web := OS.has_feature("web")
	%EditorButton.visible = not is_web
	secondary_button.visible = not is_web
	%EditorButton.pressed.connect(_navigate.bind("res://scenes/editor.tscn"))
	if not CampaignStore.last_error.is_empty():
		$Center/Panel/Margin/Content/Description.text = CampaignStore.last_error
		$Center/Panel/Margin/Content/Description.show()
	if ContentStore.saved.is_empty():
		primary_button.disabled = true
		$Center/Panel/Margin/Content/Description.text = (
			"Content could not be loaded." if is_web
			else "Content could not be loaded. Open Editor to repair it."
		)
		$Center/Panel/Margin/Content/Description.show()


func _confirm_new_campaign() -> void:
	if CampaignStore.run.is_empty():
		_new_campaign()
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Replace campaign?"
	dialog.dialog_text = "Starting a new campaign replaces your saved run."
	dialog.confirmed.connect(_new_campaign)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _new_campaign() -> void:
	if CampaignStore.new_run(ContentStore.snapshot()):
		BattleSession.campaign_node = ""
		BattleSession.campaign_camera.clear()
		_navigate("res://scenes/campaign.tscn")
	else:
		var description: Label = $Center/Panel/Margin/Content/Description
		description.text = CampaignStore.last_error
		description.show()


func _continue_campaign() -> void:
	if CampaignStore.run.is_empty(): return
	if CampaignStore.pending_battle().is_empty():
		_navigate("res://scenes/campaign.tscn")
	else:
		BattleSession.campaign_battle = true
		_navigate("res://scenes/game.tscn")


func _navigate(destination: String) -> void:
	if destination in ["res://scenes/game.tscn", "res://scenes/fleet_preparation.tscn"]:
		BattleSession.editor_playtest = false
	super._navigate(destination)
