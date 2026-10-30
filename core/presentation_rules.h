#pragma once
#include <QString>

// Browser suggestions are gated by the frontend's fullscreen signal, not titles.
inline bool isPresentationCandidate(QString app, QString title) {
    app = app.toLower();
    title = title.toLower();
    if (title.contains("presenter") || title.contains("người thuyết trình") || title.contains("speaker notes") || title.contains("presenter notes")) return false;
    const bool impress = app.contains("impress") || app.contains("libreoffice");
    return impress && (title.contains("slide show") || title.contains("slideshow"));
}
