// SPDX-License-Identifier: GPL-3.0-only

#include "presentation_rules.h"
int main() {
    if (isPresentationCandidate("firefox", "Presenting - Canva"))
        return 1;
    if (!isPresentationCandidate("libreoffice-impress", "Slide Show - lesson"))
        return 2;
    if (isPresentationCandidate("firefox", "Presentation design - Canva"))
        return 3;
    if (isPresentationCandidate("firefox", "Presenter notes - Presenting - Canva"))
        return 4;
    if (isPresentationCandidate("kitty", "Presenting - Canva"))
        return 5;
    if (isPresentationCandidate("firefox", "Cửa sổ Người thuyết trình – Bài thuyết trình"))
        return 6;
    return 0;
}
