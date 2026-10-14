extends Button
class_name FeedbackButton
## "Send feedback": opens the playtest form the build names
## (`ashes/telemetry/feedback_url` in project.godot, or --feedback-url=;
## docs/PLAYTEST.md). A build without one shows no button at all.
## "{version}" and "{locale}" in the link are filled in, so a form can be
## prefilled without asking the player.


## The button, or null when there is nowhere to send feedback to.
static func make() -> FeedbackButton:
	if Telemetry.feedback_url() == "":
		return null
	var button := FeedbackButton.new()
	button.name = "Feedback"
	button.text = "MENU_FEEDBACK"
	button.flat = true
	return button


static func link() -> String:
	return Telemetry.feedback_url() \
		.replace("{version}", str(ProjectSettings.get_setting("application/config/version", "")).uri_encode()) \
		.replace("{locale}", str(Settings.locale).uri_encode())


func _pressed() -> void:
	OS.shell_open(link())
