/*
 * SPDX-FileCopyrightText: 2019 Arjen Hiemstra <ahiemstra@heimr.nl>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#include <QApplication>
#include <QCommandLineParser>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFont>
#include <QFontDatabase>
#include <QPainter>
#include <QPixmap>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSessionManager>
#include <QSurfaceFormat>
#include <QTimer>
#include <QWindow>

#include <KAboutData>
#include <KCrash>
#include <KDBusService>
#include <KLocalizedString>
#include <KWindowSystem>

#include "CommandLineArguments.h"
#include "ToolsModel.h"

#include <KLocalizedQmlContext>

class SessionManager : public QObject
{
    Q_OBJECT
public:
    explicit SessionManager(QObject *parent);

private:
    QString m_pageId;
};

SessionManager::SessionManager(QObject *parent)
    : QObject(parent)
{
    connect(qApp, &QGuiApplication::saveStateRequest, this, [this](QSessionManager &manager) {
        QStringList args;
        args << qApp->applicationName();
        args << QStringLiteral("-session") << manager.sessionId();
        manager.setRestartCommand(args);
    });
}

int main(int argc, char **argv)
{
    auto format = QSurfaceFormat::defaultFormat();
    format.setOption(QSurfaceFormat::ResetNotification);
    QSurfaceFormat::setDefaultFormat(format);

    // Use native text rendering across all QML Text elements (matching aerothemeplasma-win7)
    QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);

    QApplication app(argc, argv);

    // Populate system faces first so lazy font discovery cannot replace the
    // application fonts with an installed font of the same family later.
    QFontDatabase::families();

    // Register only one Segoe UI version: loading the newer fallback after the
    // Windows 7 copy overrides its faces, even though the family name is identical.
    const QString referenceFontDir = QDir::homePath() + QStringLiteral("/.local/share/linux-explorer-win7/reference-fonts/");
    const QString fallbackFontDir = QDir::homePath() + QStringLiteral("/.local/share/fonts/reactxp-segoe-ui/");
    const bool hasReferenceSegoe = QFontDatabase::addApplicationFont(referenceFontDir + QStringLiteral("segoeui.ttf")) >= 0;
    const QStringList fontPaths = hasReferenceSegoe
        ? QStringList{referenceFontDir + QStringLiteral("segoeuib.ttf"), referenceFontDir + QStringLiteral("segoeuii.ttf")}
        : QStringList{fallbackFontDir + QStringLiteral("SegoeUI-Regular.ttf"),
                      fallbackFontDir + QStringLiteral("SegoeUI-Bold.ttf"),
                      fallbackFontDir + QStringLiteral("SegoeUI-Semibold.ttf"),
                      fallbackFontDir + QStringLiteral("SegoeUI-Light.ttf")};
    for (const QString &fp : fontPaths) {
        if (QFile::exists(fp)) {
            QFontDatabase::addApplicationFont(fp);
        }
    }
    QFontDatabase::addApplicationFont(referenceFontDir + QStringLiteral("tahoma.ttf"));

    // Win7's 9pt text is 12px at 96 DPI; keep it consistent with the QML geometry.
    QFont win7Font(QStringLiteral("Segoe UI"));
    win7Font.setPixelSize(12);
    win7Font.setStyleName(QStringLiteral("Regular"));
    win7Font.setHintingPreference(QFont::PreferFullHinting);
    app.setFont(win7Font);

    // Load authentic Windows 7 Task Manager icon from Windows 7 Aero icon theme (with fallback)
    QIcon taskMgrIcon;
    for (int sz : {16, 24, 32, 48, 256}) {
        const QString iconPath = QStringLiteral("/usr/share/icons/Windows 7 Aero/apps/%1/utilities-system-monitor.png").arg(sz);
        if (QFile::exists(iconPath)) {
            taskMgrIcon.addFile(iconPath, QSize(sz, sz));
        }
    }
    if (taskMgrIcon.isNull()) {
        taskMgrIcon = QIcon::fromTheme(QStringLiteral("utilities-system-monitor"));
    }
    app.setWindowIcon(taskMgrIcon);

    KLocalizedString::setApplicationDomain(QByteArrayLiteral("plasma-systemmonitor"));

    KAboutData aboutData{/* componentName */ QStringLiteral("plasma-systemmonitor"),
                         /* displayName */ i18n("Windows Task Manager"),
                         /* version */ PROJECT_VERSION,
                         /* shortDescription */ i18n("An application for monitoring system resources"),
                         /* licenseType */ KAboutLicense::GPL,
                         /* copyrightStatement */ i18n("© 2025 Plasma Development Team"),
                         /* otherText */ QString{},
                         /* homePageAddress */ QString{}};
    aboutData.setDesktopFileName(QStringLiteral("org.kde.plasma-systemmonitor"));
    aboutData.setProgramLogo(app.windowIcon());

    aboutData.addAuthor(i18n("Arjen Hiemstra"), i18n("Development"), QStringLiteral("ahiemstra@heimr.nl"));
    aboutData.addAuthor(i18n("Uri Herrera"), i18n("Design"), QStringLiteral("uri_herrera@nxos.org"));
    aboutData.addAuthor(i18n("Nate Graham"), i18n("Design and Quality Assurance"), QStringLiteral("nate@kde.org"));
    aboutData.addAuthor(i18n("David Redondo"), i18n("Development"), QStringLiteral("kde@david-redondo.de"));
    aboutData.addAuthor(i18n("Noah Davis"), i18n("Design and Quality Assurance"), QStringLiteral("noahadvs@gmail.com"));
    aboutData.addAuthor(i18n("Marco Martin"), i18n("Development"), QStringLiteral("notmart@gmail.com"));
    aboutData.addAuthor(i18n("David Edmundson"), i18n("Development"), QStringLiteral("david@davidedmundson.co.uk"));

    aboutData.setTranslator(i18ndc(nullptr, "NAME OF TRANSLATORS", "Your names"), i18ndc(nullptr, "EMAIL OF TRANSLATORS", "Your emails"));

    aboutData.setBugAddress("https://bugs.kde.org/enter_bug.cgi?product=plasma-systemmonitor");
    KAboutData::setApplicationData(aboutData);
    // Prevent Qt from appending " — Windows Task Manager" to dialog window titles like "Create New Task"
    QGuiApplication::setApplicationDisplayName(QString());

    KCrash::initialize();

    KDBusService service(KDBusService::Multiple);

    auto parser = std::make_shared<QCommandLineParser>();
    aboutData.setupCommandLine(parser.get());
    parser->addOption({QStringLiteral("page-id"), QStringLiteral("Start with the specified page ID shown"), QStringLiteral("page-id")});
    parser->addOption({QStringLiteral("page-name"), QStringLiteral("Start with the specified page name shown"), QStringLiteral("page-name")});
    parser->process(app);
    aboutData.processCommandLine(parser.get());
    CommandLineArguments::setCommandLineParser(parser);

    new SessionManager(&app);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextObject(new KLocalizedQmlContext(&engine));
    engine.loadFromModule("org.kde.systemmonitor", "Main");

    QObject::connect(&service, &KDBusService::activateRequested, &engine, []() {
        if (!qApp->topLevelWindows().isEmpty()) {
            QWindow *win = qApp->topLevelWindows().first();
            KWindowSystem::updateStartupId(win);
            KWindowSystem::activateWindow(win);
        }
    });
    // QDBusConnectionInterface::StartService is blocking so we do it manually
    const auto busInterface = QDBusConnection::sessionBus().interface();
    busInterface->asyncCall(QStringLiteral("StartServiceByName"), QStringLiteral("org.kde.ksystemstats"), 0u);

    const QString shotDir = qEnvironmentVariable("WIN7_SCREENSHOT_DIR");
    if (!shotDir.isEmpty() && !engine.rootObjects().isEmpty()) {
        QObject *rootObj = engine.rootObjects().first();
        auto *quickWin = qobject_cast<QQuickWindow *>(rootObj);
        if (quickWin) {
            struct CaptureStep {
                QString tabId;
                QString menuId;
                QString fileName;
                bool grabSecondaryWindow = false;
            };
            const QList<CaptureStep> steps = {
                {QStringLiteral("overview"), QString(), QStringLiteral("our_overview.png"), false},
                {QStringLiteral("overview"), QStringLiteral("sort_overview_cpu"), QStringLiteral("our_overview_sorted_cpu.png"), false},
                {QStringLiteral("overview"), QStringLiteral("scroll_overview_right"), QStringLiteral("our_overview_scrolled.png"), false},
                {QStringLiteral("applications"), QString(), QStringLiteral("our_applications.png"), false},
                {QStringLiteral("processes"), QString(), QStringLiteral("our_processes.png"), false},
                {QStringLiteral("processes"), QStringLiteral("sort_mem"), QStringLiteral("our_processes_sorted_mem.png"), false},
                {QStringLiteral("processes"), QStringLiteral("sort_cpu"), QStringLiteral("our_processes_sorted_cpu.png"), false},
                {QStringLiteral("processes"), QStringLiteral("scroll_proc_right"), QStringLiteral("our_processes_scrolled.png"), false},
                {QStringLiteral("performance"), QString(), QStringLiteral("our_performance.png"), false},
                {QStringLiteral("networking"), QString(), QStringLiteral("our_networking.png"), false},
                {QStringLiteral("overview"), QStringLiteral("pause_updates"), QStringLiteral("our_overview_paused.png"), false},
                {QStringLiteral("overview"), QStringLiteral("pause_updates"), QStringLiteral("our_overview_paused_again.png"), false},
                {QStringLiteral("applications"), QStringLiteral("pause_updates"), QStringLiteral("our_applications_paused.png"), false},
                {QStringLiteral("applications"), QStringLiteral("pause_updates"), QStringLiteral("our_applications_paused_again.png"), false},
                {QStringLiteral("processes"), QStringLiteral("pause_updates"), QStringLiteral("our_processes_paused.png"), false},
                {QStringLiteral("processes"), QStringLiteral("pause_updates"), QStringLiteral("our_processes_paused_again.png"), false},
                {QStringLiteral("performance"), QStringLiteral("pause_updates"), QStringLiteral("our_performance_paused.png"), false},
                {QStringLiteral("performance"), QStringLiteral("pause_updates"), QStringLiteral("our_performance_paused_again.png"), false},
                {QStringLiteral("networking"), QStringLiteral("pause_updates"), QStringLiteral("our_networking_paused.png"), false},
                {QStringLiteral("networking"), QStringLiteral("pause_updates"), QStringLiteral("our_networking_paused_again.png"), false},
                {QStringLiteral("overview"), QStringLiteral("refresh_updates"), QStringLiteral("our_overview_refreshed.png"), false},
                {QStringLiteral("overview"), QStringLiteral("normal_updates"), QStringLiteral("our_overview_resumed.png"), false},
                {QStringLiteral("processes"), QStringLiteral("file"), QStringLiteral("our_menu_file.png"), false},
                {QStringLiteral("processes"), QStringLiteral("options"), QStringLiteral("our_menu_options.png"), false},
                {QStringLiteral("performance"), QStringLiteral("view"), QStringLiteral("our_menu_view.png"), false},
                {QStringLiteral("applications"), QStringLiteral("windows"), QStringLiteral("our_menu_windows.png"), false},
                {QStringLiteral("processes"), QStringLiteral("help"), QStringLiteral("our_menu_help.png"), false},
                {QStringLiteral("processes"), QStringLiteral("ctx_proc"), QStringLiteral("our_ctx_proc.png"), false},
                {QStringLiteral("processes"), QStringLiteral("dlg_newtask"), QStringLiteral("our_dlg_newtask.png"), true},
                {QStringLiteral("processes"), QStringLiteral("dlg_about"), QStringLiteral("our_dlg_about.png"), true},
                {QStringLiteral("processes"), QStringLiteral("dlg_props"), QStringLiteral("our_dlg_props.png"), true},
                {QStringLiteral("processes"), QStringLiteral("dlg_cols"), QStringLiteral("our_dlg_cols.png"), true},
            };
            // Advance only after the preceding image has been saved. Independent
            // timers could overlap and save the next tab/dialog under the old name.
            auto *captureTimer = new QTimer(quickWin);
            captureTimer->setSingleShot(true);
            QObject::connect(captureTimer, &QTimer::timeout, quickWin,
                             [quickWin, rootObj, shotDir, steps, captureTimer, stepIndex = 0]() mutable {
                    const auto step = steps.at(stepIndex++);
                    const bool lastStep = stepIndex == steps.size();
                    rootObj->setProperty("debugOpenMenu", QString());
                    rootObj->setProperty("currentTabId", step.tabId);
                    QTimer::singleShot(200, Qt::PreciseTimer, quickWin, [quickWin, rootObj, step, lastStep, shotDir, captureTimer]() {
                        rootObj->setProperty("debugOpenMenu", step.menuId);
                        QTimer::singleShot(450, Qt::PreciseTimer, quickWin, [quickWin, rootObj, step, lastStep, shotDir, captureTimer]() {
                            QQuickWindow *targetWin = quickWin;
                            if (step.grabSecondaryWindow) {
                                targetWin = qobject_cast<QQuickWindow *>(rootObj->property("debugCaptureWindow").value<QObject *>());
                                if (!targetWin || !targetWin->isVisible()) {
                                    qWarning() << "Screenshot dialog is not visible:" << step.fileName;
                                    qApp->exit(1);
                                    return;
                                }
                            }
                            const QImage img = targetWin->grabWindow();
                            if (img.isNull() || !img.save(shotDir + QLatin1Char('/') + step.fileName)) {
                                qWarning() << "Could not save screenshot:" << step.fileName;
                                qApp->exit(1);
                                return;
                            }
                            qInfo() << "Captured" << step.fileName << img.size();
                            if (targetWin != quickWin) {
                                targetWin->close();
                            }
                            if (lastStep) {
                                qApp->quit();
                            } else {
                                captureTimer->start(250);
                            }
                        });
                    });
            });
            captureTimer->start(2500);
        }
    }

    return app.exec();
}

#include "main.moc"
