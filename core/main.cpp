// SPDX-License-Identifier: GPL-3.0-only

#include "presentation_rules.h"
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QTextStream>
#include <algorithm>
#include <stdexcept>

namespace {
using Object = QJsonObject;
using Array = QJsonArray;

[[noreturn]] void fail(const QString &message) { throw std::runtime_error(message.toStdString()); }

// Niri's socket protocol returns one newline-delimited JSON reply per request.
QJsonValue request(const QByteArray &payload) {
    const QString path = qEnvironmentVariable("NIRI_SOCKET");
    if (path.isEmpty())
        fail("NIRI_SOCKET is not set; start this command in a Niri session.");
    QLocalSocket socket;
    socket.connectToServer(path);
    if (!socket.waitForConnected(5000))
        fail("Cannot connect to Niri: " + socket.errorString());
    if (socket.write(payload + '\n') < 0 || !socket.waitForBytesWritten(5000))
        fail("Cannot send request to Niri: " + socket.errorString());
    QByteArray response;
    while (!response.contains('\n')) {
        if (!socket.bytesAvailable() && !socket.waitForReadyRead(5000))
            fail("Cannot read response from Niri: " + socket.errorString());
        response += socket.readAll();
        // Bound memory even if the peer returns a malformed or oversized reply.
        if (response.size() > 16 * 1024 * 1024)
            fail("Niri response is too large.");
    }
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(response.left(response.indexOf('\n')), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
        fail("Invalid JSON response from Niri.");
    const auto reply = document.object();
    if (reply.contains("Err"))
        fail("Niri error: " + reply.value("Err").toString());
    if (!reply.contains("Ok"))
        fail("Unexpected response from Niri.");
    return reply.value("Ok");
}

QJsonValue query(const char *name) {
    QByteArray payload = "\"" + QByteArray(name) + "\"";
    auto value = request(payload);
    if (!value.isObject() || !value.toObject().contains(name))
        fail("Unexpected Niri response for " + QString::fromLatin1(name));
    return value.toObject().value(name);
}

Object snapshot() {
    // Separate requests can observe different compositor states; callers must
    // validate again before acting on a snapshot.
    auto outValue = query("Outputs"), wsValue = query("Workspaces"), winValue = query("Windows");
    if (!outValue.isObject() || !wsValue.isArray() || !winValue.isArray())
        fail("Unexpected Niri state format.");
    const auto outputMap = outValue.toObject();
    QList<Object> sorted;
    for (auto it = outputMap.begin(); it != outputMap.end(); ++it) {
        auto output = it.value().toObject();
        if (output.value("logical").isObject())
            sorted.append(output);
    }
    std::sort(sorted.begin(), sorted.end(), [](const Object &a, const Object &b) {
        return a.value("name").toString() < b.value("name").toString();
    });
    Array outputs, windows;
    for (const auto &item : sorted)
        outputs.append(item);
    const auto workspaces = wsValue.toArray();
    for (const auto &item : winValue.toArray()) {
        Object window = item.toObject();
        QJsonValue output = QJsonValue::Null;
        for (const auto &ws : workspaces) {
            if (ws.toObject().value("id") == window.value("workspace_id")) {
                output = ws.toObject().value("output");
                break;
            }
        }
        window.insert("output", output);
        window.insert("presentation_candidate",
                      isPresentationCandidate(window.value("app_id").toString(),
                                              window.value("title").toString()));
        windows.append(window);
    }
    return {{"outputs", outputs}, {"windows", windows}};
}

Object move(qint64 id, const QString &output) {
    if (id <= 0 || output.isEmpty())
        fail("A valid window ID and output are required.");
    const Object before = snapshot();
    bool foundOutput = false, foundWindow = false;
    for (const auto &o : before.value("outputs").toArray())
        foundOutput |= o.toObject().value("name").toString() == output;
    for (const auto &w : before.value("windows").toArray())
        foundWindow |= w.toObject().value("id").toInteger() == id;
    if (!foundOutput)
        fail("The destination display is not available.");
    if (!foundWindow)
        fail("The window no longer exists.");
    Object action{
        {"Action", Object{{"MoveWindowToMonitor", Object{{"id", id}, {"output", output}}}}}};
    request(QJsonDocument(action).toJson(QJsonDocument::Compact));
    // A successful IPC action means accepted, not necessarily applied.
    const Object after = snapshot();
    for (const auto &w : after.value("windows").toArray()) {
        const Object item = w.toObject();
        if (item.value("id").toInteger() == id && item.value("output").toString() == output)
            return {{"window_id", id}, {"output", output}};
    }
    fail("Could not confirm that the window moved to the destination display.");
}
} // namespace

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    QCommandLineParser parser;
    parser.setApplicationDescription("Presentation Hub Niri core (JSON output)");
    parser.addHelpOption();
    parser.addPositionalArgument("command", "snapshot or move");
    parser.addOption({"window", "Window ID", "id"});
    parser.addOption({"output", "Destination output", "name"});
    parser.process(app);
    const auto args = parser.positionalArguments();
    try {
        Object result;
        if (args.size() == 1 && args[0] == "snapshot" && !parser.isSet("window") &&
            !parser.isSet("output"))
            result = snapshot();
        else if (args.size() == 1 && args[0] == "move" && parser.isSet("window") &&
                 parser.isSet("output")) {
            bool ok = false;
            const auto id = parser.value("window").toLongLong(&ok);
            if (!ok)
                fail("A valid window ID is required.");
            result = move(id, parser.value("output"));
        } else
            fail("Usage: presentation-hub-core snapshot | move --window ID --output NAME");
        QTextStream(stdout) << QJsonDocument(result).toJson(QJsonDocument::Compact) << Qt::endl;
        return 0;
    } catch (const std::exception &e) {
        QTextStream(stderr) << e.what() << Qt::endl;
        return 1;
    }
}
