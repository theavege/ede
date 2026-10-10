cmake_minimum_required(VERSION 3.16)

project(EDE
	VERSION 2.2.0
	DESCRIPTION "Equinox Desktop Environment"
	LANGUAGES C CXX
)

set(CMAKE_CXX_STANDARD 98)
set(CMAKE_CXX_STANDARD_REQUIRED OFF)
set(CMAKE_CXX_EXTENSIONS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
	set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Build type" FORCE)
endif()

include(GNUInstallDirs)
include(CheckIncludeFile)
include(CheckIncludeFileCXX)
include(CheckFunctionExists)
include(CheckSymbolExists)
include(CheckLibraryExists)
include(CheckCXXSourceCompiles)
include(CheckCSourceCompiles)
include(CMakeDependentOption)
include(FindPkgConfig)

option(ENABLE_DEBUG "Build with extra debug macros" OFF)
option(ENABLE_SHAPE "Enable XShape extension" ON)
option(ENABLE_COMPOSITE "Enable XComposite extension" ON)
option(ENABLE_HAL "Enable HAL support (legacy)" OFF)
option(ENABLE_LARGEFILE "Enable large file support" OFF)
option(BUILD_PEKWM "Build the bundled pekwm window manager" ON)
option(BUILD_PANEL "Build ede-panel and applets" ON)
option(BUILD_ICON_THEMES "Install icon themes" OFF)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(EdeHelpers)

# ---------------------------------------------------------------------------
# Feature probes (mirrors configure.in)
# ---------------------------------------------------------------------------

check_function_exists(pselect HAVE_PSELECT)
check_function_exists(setgroups HAVE_SETGROUPS)
check_function_exists(asprintf HAVE_ASPRINTF)
check_function_exists(setenv HAVE_SETENV)
check_function_exists(unsetenv HAVE_UNSETENV)
check_function_exists(wcsncmp HAVE_WCSNCMP)
check_function_exists(gettimeofday HAVE_GETTIMEOFDAY)
check_function_exists(localtime_r HAVE_LOCALTIME_R)
check_function_exists(gmtime_r HAVE_GMTIME_R)
check_function_exists(strcasecmp HAVE_STRCASECMP)
check_function_exists(swprintf HAVE_SWPRINTF)
check_function_exists(iconvctl HAVE_ICONVCTL)

check_include_file_cxx("limits" HAVE_LIMITS)
check_include_file_cxx("slist" HAVE_SLIST)
check_include_file_cxx("ext/slist" HAVE_EXT_SLIST)
check_include_file("sys/vfs.h" HAVE_SYS_VFS_H)

if(HAVE_SYS_VFS_H)
	check_c_source_compiles("
		#include <sys/vfs.h>
		int main(void) { struct statfs s; statfs(\"/\", &s); return 0; }
	" HAVE_STATFS)
endif()

check_c_source_compiles("
	#include <sys/time.h>
	INT_MAIN_TIMERSUB
" HAVE_TIMERSUB)

check_c_source_compiles("
	#include <stdarg.h>
	int main(void) { va_list list1, list2; list1 = list2; return 0; }
" VA_LIST_ASSIGNABLE)
if(NOT VA_LIST_ASSIGNABLE)
	set(VA_LIST_IS_ARRAY 1)
endif()

set(SLIST_NAMESPACE "std")
if(HAVE_EXT_SLIST OR HAVE_SLIST)
	check_cxx_source_compiles("
		#ifdef HAVE_SLIST
		#include <slist>
		#else
		#include <ext/slist>
		#endif
		int main() { std::slist<int> test; return 0; }
	" SLIST_IN_STD)
	if(SLIST_IN_STD)
		set(SLIST_NAMESPACE "std")
	else()
		set(SLIST_NAMESPACE "__gnu_cxx")
	endif()
endif()

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

find_package(Threads REQUIRED)
find_package(X11 REQUIRED)
find_package(PkgConfig REQUIRED)

pkg_check_modules(EDELIB REQUIRED IMPORTED_TARGET edelib)
pkg_check_modules(EDELIB_GUI REQUIRED IMPORTED_TARGET edelib-gui)
pkg_check_modules(EDELIB_GUI_NO_IMAGES REQUIRED IMPORTED_TARGET edelib-gui-no-images)
pkg_check_modules(EDELIB_DBUS IMPORTED_TARGET edelib-dbus)

find_program(FLTK_CONFIG_EXECUTABLE fltk-config)
if(NOT FLTK_CONFIG_EXECUTABLE)
	message(FATAL_ERROR "fltk-config not found. Install FLTK >= 1.1.7 (1.3.x recommended).")
endif()

execute_process(
	COMMAND ${FLTK_CONFIG_EXECUTABLE} --version
	OUTPUT_VARIABLE FLTK_VERSION
	OUTPUT_STRIP_TRAILING_WHITESPACE
)
message(STATUS "Found FLTK ${FLTK_VERSION}")

pkg_check_modules(XCOMPOSITE xcomposite)
pkg_check_modules(XDAMAGE xdamage)
pkg_check_modules(XEXT xext)
pkg_check_modules(XFT xft>=2.0.0)
pkg_check_modules(XRANDR xrandr>=1.2.0)
pkg_check_modules(LIBPNG libpng)
if(NOT LIBPNG_FOUND)
	pkg_check_modules(LIBPNG libpng12)
endif()
pkg_check_modules(LIBSN libstartup-notification-1.0)
pkg_check_modules(LIBCURL libcurl)

if(ENABLE_COMPOSITE AND XCOMPOSITE_FOUND AND XDAMAGE_FOUND AND XEXT_FOUND)
	set(HAVE_COMPOSITE 1)
endif()

if(ENABLE_SHAPE)
	check_include_file("X11/extensions/shape.h" HAVE_XSHAPE_H)
	if(HAVE_XSHAPE_H AND X11_Xext_FOUND)
		set(HAVE_SHAPE 1)
		set(XSHAPE_LIBRARIES ${X11_Xext_LIB})
	endif()
endif()

if(LIBSN_FOUND)
	set(HAVE_LIBSTARTUP_NOTIFICATION 1)
endif()

if(LIBCURL_FOUND)
	set(HAVE_CURL 1)
	check_include_file("curl/types.h" HAVE_CURLTYPES_H)
endif()

if(X11_Xkb_FOUND OR EXISTS "${X11_INCLUDE_DIR}/X11/extensions/XKBrules.h")
	find_library(XKBFILE_LIBRARY xkbfile)
	if(XKBFILE_LIBRARY)
		set(HAVE_XKBRULES 1)
	endif()
endif()

find_library(XINERAMA_LIBRARY Xinerama)
if(XINERAMA_LIBRARY)
	set(HAVE_XINERAMA 1)
endif()

if(XFT_FOUND)
	set(HAVE_XFT 1)
endif()

if(XRANDR_FOUND)
	set(HAVE_XRANDR 1)
endif()

find_library(XPM_LIBRARY Xpm)
if(XPM_LIBRARY)
	set(HAVE_IMAGE_XPM 1)
endif()

find_library(JPEG_LIBRARY jpeg)
if(JPEG_LIBRARY)
	check_include_file("jpeglib.h" HAVE_JPEGLIB_H)
	if(HAVE_JPEGLIB_H)
		set(HAVE_IMAGE_JPEG 1)
	endif()
endif()

if(LIBPNG_FOUND)
	set(HAVE_IMAGE_PNG 1)
endif()

if(ENABLE_HAL)
	pkg_check_modules(HAL hal)
	if(HAL_FOUND)
		set(HAVE_HAL 1)
	endif()
endif()

find_library(KSTAT_LIBRARY kstat)
if(KSTAT_LIBRARY)
	set(HAVE_KSTAT 1)
endif()

set(PEKWM_FEATURES "")
set(PEKWM_LIBS ${X11_LIBRARIES} ${X11_Xext_LIB})
set(PEKWM_CXXFLAGS "")

if(HAVE_XINERAMA)
	list(APPEND PEKWM_LIBS ${XINERAMA_LIBRARY})
	string(APPEND PEKWM_FEATURES " Xinerama")
endif()
if(HAVE_XFT)
	list(APPEND PEKWM_LIBS ${XFT_LIBRARIES})
	string(APPEND PEKWM_FEATURES " Xft")
endif()
if(HAVE_XRANDR)
	list(APPEND PEKWM_LIBS ${XRANDR_LIBRARIES})
	string(APPEND PEKWM_FEATURES " Xrandr")
endif()
if(HAVE_IMAGE_XPM)
	list(APPEND PEKWM_LIBS ${XPM_LIBRARY})
	string(APPEND PEKWM_FEATURES " image-xpm")
endif()
if(HAVE_IMAGE_JPEG)
	list(APPEND PEKWM_LIBS ${JPEG_LIBRARY})
	string(APPEND PEKWM_FEATURES " image-jpeg")
endif()
if(HAVE_IMAGE_PNG)
	list(APPEND PEKWM_LIBS ${LIBPNG_LIBRARIES})
	string(APPEND PEKWM_FEATURES " image-png")
endif()

if(ENABLE_DEBUG OR CMAKE_BUILD_TYPE STREQUAL "Debug")
	add_compile_definitions(_DEBUG DEBUG)
	add_compile_options(-g3)
endif()

if(ENABLE_LARGEFILE)
	add_compile_definitions(_LARGEFILE_SOURCE _LARGEFILE64_SOURCE _FILE_OFFSET_BITS=64)
endif()

set(HAVE_CONFIG_H 1)
add_compile_definitions(HAVE_CONFIG_H)

configure_file(
	${CMAKE_CURRENT_SOURCE_DIR}/cmake/config.h.in
	${CMAKE_CURRENT_BINARY_DIR}/config.h
)

# Generated runtime files (replaces AC_OUTPUT templates)
set(prefix ${CMAKE_INSTALL_PREFIX})
set(my_sysconfdir ${CMAKE_INSTALL_FULL_SYSCONFDIR})
set(ededocdir ${CMAKE_INSTALL_FULL_DATADIR}/doc/ede-${PROJECT_VERSION})
configure_file(${CMAKE_SOURCE_DIR}/data/startede.in ${CMAKE_BINARY_DIR}/startede @ONLY)
configure_file(${CMAKE_SOURCE_DIR}/data/ede.desktop.in ${CMAKE_BINARY_DIR}/ede.desktop @ONLY)
configure_file(${CMAKE_SOURCE_DIR}/services/org.equinoxproject.Launch.service.in
	${CMAKE_BINARY_DIR}/org.equinoxproject.Launch.service @ONLY)
configure_file(${CMAKE_SOURCE_DIR}/ede-help/ede-help.in ${CMAKE_BINARY_DIR}/ede-help @ONLY)

# ---------------------------------------------------------------------------
# Applications
# ---------------------------------------------------------------------------

ede_program(ede-about SOURCES ede-about/ede-about.cpp)
ede_program(ede-autostart SOURCES ede-autostart/ede-autostart.cpp)
ede_program(ede-bell-conf SOURCES ede-bell-conf/ede-bell-conf.cpp)
ede_program(ede-calc SOURCES ede-calc/SciCalc.cpp ede-calc/Main.cpp FLTK_BARE)
ede_program(ede-conf SOURCES ede-conf/ede-conf.cpp)
ede_program(ede-desktop-conf SOURCES ede-desktop-conf/ede-desktop-conf.cpp)
ede_program(ede-dialog SOURCES ede-dialog/ede-dialog.cpp)
ede_program(ede-image-view SOURCES ede-image-view/ede-image-view.cpp)
ede_program(ede-timedate SOURCES ede-timedate/ede-timedate.cpp ede-timedate/EDE_Calendar.cpp)
ede_program(ede-preferred-applications
	SOURCES
		ede-preferred-applications/ede-preferred-applications.cpp
		ede-preferred-applications/AppChoice.cpp
)
ede_program(ede-screensaver-conf
	SOURCES
		ede-screensaver-conf/ede-screensaver-conf.cpp
		ede-screensaver-conf/XScreenSaver.cpp
)
ede_program(ede-crasher
	SOURCES
		ede-bug-tools/ede-crasher/ede-crasher.cpp
		ede-bug-tools/ede-crasher/GdbOutput.cpp
		ede-bug-tools/ede-crasher/CrashDialog.cpp
)

set(DESKTOP_LIBS)
if(TARGET PkgConfig::EDELIB_DBUS)
	list(APPEND DESKTOP_LIBS PkgConfig::EDELIB_DBUS)
endif()
if(XSHAPE_LIBRARIES)
	list(APPEND DESKTOP_LIBS ${XSHAPE_LIBRARIES})
endif()
list(APPEND DESKTOP_LIBS Threads::Threads)

ede_program(ede-desktop
	SOURCES
		ede-desktop/ede-desktop.cpp
		ede-desktop/Wallpaper.cpp
		ede-desktop/DesktopIcon.cpp
		ede-desktop/MovableIcon.cpp
		ede-desktop/Utils.cpp
		ede-desktop/IconDialog.cpp
		ede-desktop/Desktop.cpp
	DEFINITIONS USE_EDELIB_WINDOW
	LIBRARIES ${DESKTOP_LIBS}
)

set(KEYBOARD_LIBS)
if(HAVE_XKBRULES AND XKBFILE_LIBRARY)
	list(APPEND KEYBOARD_LIBS ${XKBFILE_LIBRARY} ${X11_LIBRARIES})
endif()
ede_program(ede-keyboard-conf
	SOURCES ede-keyboard-conf/ede-keyboard-conf.cpp
	LIBRARIES ${KEYBOARD_LIBS}
)

set(NOTIFY_LIBS Threads::Threads)
if(TARGET PkgConfig::EDELIB_DBUS)
	list(APPEND NOTIFY_LIBS PkgConfig::EDELIB_DBUS)
endif()
ede_program(ede-notify-daemon
	SOURCES
		ede-notify-daemon/ede-notify-daemon.cpp
		ede-notify-daemon/NotifyWindow.cpp
	LIBRARIES ${NOTIFY_LIBS}
)

set(LAUNCH_LIBS)
if(HAVE_LIBSTARTUP_NOTIFICATION)
	list(APPEND LAUNCH_LIBS ${LIBSN_LIBRARIES})
endif()
ede_program(ede-launch
	SOURCES
		ede-launch/ede-launch.cpp
		ede-launch/StartupNotify.cpp
	INCLUDES ${LIBSN_INCLUDE_DIRS}
	LIBRARIES ${LAUNCH_LIBS}
)

set(EVOKE_LIBS Threads::Threads)
if(TARGET PkgConfig::EDELIB_DBUS)
	list(APPEND EVOKE_LIBS PkgConfig::EDELIB_DBUS)
endif()
ede_program(evoke
	SOURCES
		evoke/evoke.cpp
		evoke/EvokeService.cpp
		evoke/Splash.cpp
		evoke/Xsm.cpp
		evoke/Logout.cpp
		evoke/Xshutdown.cpp
	DEFINITIONS EDEWM_HAVE_NET_SPLASH USE_SIGHUP
	LIBRARIES ${EVOKE_LIBS}
)

ede_program(ede-shutdown
	SOURCES evoke/ede-shutdown.cpp
	BARE
	LIBRARIES ${X11_LIBRARIES} m
)

ede_program(ede-tip
	SOURCES ede-tip/Fortune.cpp ede-tip/ede-tip.cpp
)
ede_program(ede-tip-compiler
	SOURCES ede-tip/ede-tip-compiler.c
	BARE
	LIBRARIES m
)

add_custom_command(
	OUTPUT ${CMAKE_BINARY_DIR}/ede.dat
	COMMAND ede-tip-compiler -s ${CMAKE_SOURCE_DIR}/ede-tip/tips/ede ${CMAKE_BINARY_DIR}/ede.dat
	DEPENDS ede-tip-compiler ${CMAKE_SOURCE_DIR}/ede-tip/tips/ede
	COMMENT "Compiling EDE tips"
)
add_custom_target(ede-tips ALL DEPENDS ${CMAKE_BINARY_DIR}/ede.dat)

set(BUG_REPORT_SOURCES ede-bug-tools/ede-bug-report/ede-bug-report.cpp)
if(HAVE_CURL)
	list(APPEND BUG_REPORT_SOURCES
		ede-bug-tools/ede-bug-report/Bugzilla.cpp
		ede-bug-tools/ede-bug-report/BugzillaSender.cpp
		ede-bug-tools/ede-bug-report/PulseProgress.cpp
	)
endif()
ede_program(ede-bug-report
	SOURCES ${BUG_REPORT_SOURCES}
	LIBRARIES $<$<BOOL:${HAVE_CURL}>:${LIBCURL_LIBRARIES}> Threads::Threads
	INCLUDES
		${CMAKE_SOURCE_DIR}/ede-bug-tools/ede-bug-report
		${CMAKE_SOURCE_DIR}/ede-bug-tools/ede-bug-report/xmlrpc-c
		${CMAKE_SOURCE_DIR}/ede-bug-tools/ede-bug-report/xmlrpc-c/include
)

if(BUILD_PANEL)
	ede_program(ede-panel
		SOURCES
			ede-panel/Hider.cpp
			ede-panel/Panel.cpp
			ede-panel/AppletManager.cpp
			ede-panel/ede-panel.cpp
		LIBRARIES ${CMAKE_DL_LIBS}
	)
	if(NOT CMAKE_SYSTEM_NAME STREQUAL "SunOS")
		target_link_options(ede-panel PRIVATE -rdynamic)
	endif()

	ede_panel_applet(clock SOURCES ede-panel/applets/clock/Clock.cpp)
	ede_panel_applet(cpu_monitor
		SOURCES ede-panel/applets/cpu-monitor/CpuMonitor.cpp
		LIBRARIES $<$<BOOL:${HAVE_KSTAT}>:${KSTAT_LIBRARY}>
	)
	ede_panel_applet(mem_monitor SOURCES ede-panel/applets/mem-monitor/MemMonitor.cpp)
	set(BATTERY_LIBS)
	if(TARGET PkgConfig::EDELIB_DBUS)
		list(APPEND BATTERY_LIBS PkgConfig::EDELIB_DBUS)
	endif()
	ede_panel_applet(battery_monitor
		SOURCES ede-panel/applets/battery-monitor/BatteryMonitor.cpp
		LIBRARIES ${BATTERY_LIBS}
	)
	ede_panel_applet(keyboard_layout
		SOURCES ede-panel/applets/keyboard-layout/KeyLayout.cpp
		LIBRARIES ${KEYBOARD_LIBS}
	)
	ede_panel_applet(pager
		SOURCES
			ede-panel/applets/pager/Pager.cpp
			ede-panel/applets/pager/PagerButton.cpp
	)
	ede_panel_applet(quick_launch SOURCES ede-panel/applets/quick-launch/QuickLaunch.cpp)
	ede_panel_applet(start_menu
		SOURCES
			ede-panel/applets/start-menu/StartMenu.cpp
			ede-panel/applets/start-menu/XdgMenuReader.cpp
			ede-panel/applets/start-menu/DesktopEntry.cpp
			ede-panel/applets/start-menu/MenuRules.cpp
	)
	ede_panel_applet(system_tray SOURCES ede-panel/applets/system-tray/Tray.cpp)
	ede_panel_applet(taskbar
		SOURCES
			ede-panel/applets/taskbar/TaskButton.cpp
			ede-panel/applets/taskbar/Taskbar.cpp
	)
endif()

if(BUILD_PEKWM)
	set(PEKWM_SOURCES
		pekwm/ActionHandler.cc
		pekwm/ActionMenu.cc
		pekwm/Atoms.cc
		pekwm/AutoProperties.cc
		pekwm/CfgParser.cc
		pekwm/CfgParserKey.cc
		pekwm/CfgParserSource.cc
		pekwm/Client.cc
		pekwm/CmdDialog.cc
		pekwm/ColorHandler.cc
		pekwm/Compat.cc
		pekwm/Completer.cc
		pekwm/Config.cc
		pekwm/DecorMenu.cc
		pekwm/DockApp.cc
		pekwm/FontHandler.cc
		pekwm/Frame.cc
		pekwm/FrameListMenu.cc
		pekwm/Harbour.cc
		pekwm/HarbourMenu.cc
		pekwm/ImageHandler.cc
		pekwm/InputDialog.cc
		pekwm/KeyGrabber.cc
		pekwm/main.cc
		pekwm/ManagerWindows.cc
		pekwm/MenuHandler.cc
		pekwm/Observable.cc
		pekwm/PDecor.cc
		pekwm/PFont.cc
		pekwm/PImage.cc
		pekwm/PImageIcon.cc
		pekwm/PImageLoaderJpeg.cc
		pekwm/PImageLoaderPng.cc
		pekwm/PImageLoaderXpm.cc
		pekwm/PixmapHandler.cc
		pekwm/PMenu.cc
		pekwm/PScreen.cc
		pekwm/PTexturePlain.cc
		pekwm/PWinObj.cc
		pekwm/PWinObjReference.cc
		pekwm/RegexString.cc
		pekwm/ScreenResources.cc
		pekwm/SearchDialog.cc
		pekwm/StatusWindow.cc
		pekwm/TextureHandler.cc
		pekwm/Theme.cc
		pekwm/Util.cc
		pekwm/WindowManager.cc
		pekwm/WORefMenu.cc
		pekwm/WorkspaceIndicator.cc
		pekwm/Workspaces.cc
	)
	add_executable(pekwm ${PEKWM_SOURCES})
	target_compile_definitions(pekwm PRIVATE
		HAVE_CONFIG_H
		DATADIR="${CMAKE_INSTALL_FULL_DATADIR}"
		SYSCONFDIR="${CMAKE_INSTALL_FULL_SYSCONFDIR}/pekwm"
		VERSION="0.1.13"
	)
	target_include_directories(pekwm PRIVATE
		${CMAKE_BINARY_DIR}
		${CMAKE_SOURCE_DIR}
		${X11_INCLUDE_DIR}
		${XFT_INCLUDE_DIRS}
		${XRANDR_INCLUDE_DIRS}
		${LIBPNG_INCLUDE_DIRS}
	)
	target_compile_options(pekwm PRIVATE -Wall)
	target_link_libraries(pekwm PRIVATE ${PEKWM_LIBS})
	install(TARGETS pekwm RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()

# ---------------------------------------------------------------------------
# Scripts and data
# ---------------------------------------------------------------------------

install(PROGRAMS
	${CMAKE_BINARY_DIR}/startede
	${CMAKE_BINARY_DIR}/ede-help
	${CMAKE_SOURCE_DIR}/ede-screen-lock/ede-screen-lock
	${CMAKE_SOURCE_DIR}/evoke/ede-settings-apply
	DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(FILES ${CMAKE_BINARY_DIR}/ede.desktop
	DESTINATION ${CMAKE_INSTALL_DATADIR}/xsessions
)

install(FILES
	${CMAKE_SOURCE_DIR}/ede-conf/ede-conf.conf
	${CMAKE_SOURCE_DIR}/evoke/ede-settings.conf
	${CMAKE_SOURCE_DIR}/evoke/ede-startup.conf
	DESTINATION ${CMAKE_INSTALL_SYSCONFDIR}/xdg/ede
)

install(FILES ${CMAKE_BINARY_DIR}/org.equinoxproject.Launch.service
	DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services
)

install(FILES
	${CMAKE_BINARY_DIR}/ede.dat
	${CMAKE_SOURCE_DIR}/ede-tip/tips/ede
	DESTINATION ${CMAKE_INSTALL_DATADIR}/ede/tips
)

message(STATUS "EDE ${PROJECT_VERSION}")
message(STATUS "  prefix     : ${CMAKE_INSTALL_PREFIX}")
message(STATUS "  FLTK       : ${FLTK_VERSION}")
message(STATUS "  edelib     : ${EDELIB_VERSION}")
message(STATUS "  composite  : ${HAVE_COMPOSITE}")
message(STATUS "  shape      : ${HAVE_SHAPE}")
message(STATUS "  dbus       : ${EDELIB_DBUS_FOUND}")
message(STATUS "  pekwm      : ${BUILD_PEKWM}")
message(STATUS "  panel      : ${BUILD_PANEL}")
