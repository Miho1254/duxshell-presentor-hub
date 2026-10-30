// SPDX-License-Identifier: GPL-3.0-only

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "presentationHub"

    StyledText {
        width: parent.width
        text: "Browser detection"
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
    }

    SelectionSetting {
        settingKey: "suggestionMode"
        label: "Presentation suggestions"
        description: "Choose when fullscreen browser suggestions can appear. Manual only also disables presentation-window suggestions."
        options: [{
            "label": "Ask for browser fullscreen",
            "value": "always"
        }, {
            "label": "Only during a session",
            "value": "session"
        }, {
            "label": "Manual only",
            "value": "manual"
        }]
        defaultValue: "always"
    }

    SelectionSetting {
        settingKey: "browserFilter"
        label: "Browser app ID filter"
        description: "Apply the list below to browser fullscreen suggestions."
        options: [{
            "label": "All detected browsers",
            "value": "all"
        }, {
            "label": "Only listed IDs",
            "value": "only"
        }, {
            "label": "Exclude listed IDs",
            "value": "exclude"
        }]
        defaultValue: "all"
    }

    StringSetting {
        settingKey: "browserFilterIds"
        label: "Browser filter app IDs"
        description: "Comma-separated exact app IDs. Find IDs using niri msg windows."
        placeholder: "firefox, chromium"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "coverImage"
        label: "Audience cover image"
        description: "Optional absolute path to an image. Leave empty for a black screen. Images fit within the screen with black margins."
        placeholder: "/home/user/Pictures/cover.png"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "additionalBrowserAppIds"
        label: "Additional browser app IDs"
        description: "Comma-separated exact app IDs for browsers that are not detected automatically. Find an app ID with niri msg windows."
        placeholder: "org.example.Browser, another-browser"
        defaultValue: ""
    }

}
