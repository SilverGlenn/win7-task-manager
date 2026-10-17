add_subdirectory(page)
add_subdirectory(table)
add_subdirectory(faces)


add_definitions(-DQT_NO_KEYWORDS)

add_executable(plasma-systemmonitor ${plasma-systemmonitor_SRCS} ${plasma-systemmonitor_QRC})
ecm_add_qml_module(plasma-systemmonitor URI "org.kde.systemmonitor" GENERATE_PLUGIN_SOURCE DEPENDENCIES "QtCore")

target_sources(plasma-systemmonitor PRIVATE
    main.cpp
    ToolsModel.cpp
    ToolsModel.h
    CommandLineArguments.cpp
    CommandLineArguments.h
    Win7SnapshotModel.cpp
    Win7SnapshotModel.h
    Win7SystemStatistics.cpp
    Win7SystemStatistics.h
    Win7NetworkConnections.cpp
    Win7NetworkConnections.h
    Win7NetworkProcessModel.cpp
    Win7NetworkProcessModel.h
)

ecm_target_qml_sources(plasma-systemmonitor SOURCES
    Main.qml
    GlobalMenu.qml
    Win7UpdateClock.qml
    Win7Sensor.qml
    Win7Button.qml
    Win7ProcessFormat.js
    Win7ScrollBar.qml
    Win7GroupBox.qml
    Win7Gauge.qml
    Win7HistoryGraph.qml
    Win7Menu.qml
    Win7MenuItem.qml
    Win7MenuSeparator.qml
    Win7OverviewTab.qml
    Win7ApplicationsTab.qml
    Win7ProcessesTab.qml
    Win7PerformanceTab.qml
    Win7NetworkingTab.qml
    Win7NetworkProcessesView.qml
    Win7NewTaskDialog.qml
    Win7AboutDialog.qml
)


target_compile_definitions(plasma-systemmonitor PRIVATE PROJECT_VERSION="${PROJECT_VERSION}")
target_link_libraries(plasma-systemmonitor PRIVATE
    Qt::Quick
    Qt::Widgets
    Qt::DBus
    Qt::Concurrent
    KF6::I18n
    KF6::ConfigGui
    KF6::Crash
    KF6::Service
    KF6::KIOGui
    KF6::GlobalAccel
    KF6::DBusAddons
    KF6::WindowSystem
    PlasmaSystemMonitorPage
    PlasmaSystemMonitorTable
)

if(TARGET KF6::I18nQml)
    target_link_libraries(plasma-systemmonitor PRIVATE
       KF6::I18nQml
)
endif()

install(TARGETS plasma-systemmonitor DESTINATION ${KDE_INSTALL_BINDIR})
install(FILES plasma-systemmonitor.knsrc DESTINATION ${KDE_INSTALL_KNSRCDIR})

install(FILES
    pages/applications.page
    pages/history.page
    pages/overview.page
    pages/processes.page
    pages/old-history.page
    pages/old-overview.page
    DESTINATION ${KDE_INSTALL_DATADIR}/plasma-systemmonitor
    PERMISSIONS OWNER_READ GROUP_READ WORLD_READ
)

ecm_finalize_qml_module(plasma-systemmonitor)
