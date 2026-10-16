/* Targeted playback control for Wallpaper Engine 2.8.42 scene pop-out windows.
 * Derived from original renderer::Pause message sender/receiver; no code injection.
 * Delivery success does not independently prove simulation/media paused.
 */
#ifndef UNICODE
#define UNICODE 1
#endif
#ifndef _UNICODE
#define _UNICODE 1
#endif
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <wchar.h>
#include <stdlib.h>
#include <errno.h>
#include <stdint.h>

struct match { const wchar_t *title; HWND top, child; DWORD pid; unsigned tops, children; };
static BOOL CALLBACK find_top(HWND hwnd, LPARAM context)
{
    struct match *m = (void *)context;
    wchar_t title[256];
    if (GetWindowTextLengthW(hwnd) != (int)wcslen(m->title)) return TRUE;
    if (!GetWindowTextW(hwnd, title, 256) || wcscmp(title, m->title)) return TRUE;
    m->tops++;
    m->top = hwnd;
    GetWindowThreadProcessId(hwnd, &m->pid);
    return TRUE;
}
static BOOL CALLBACK find_child(HWND hwnd, LPARAM context)
{
    struct match *m = (void *)context;
    wchar_t name[128], title[128]; DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid != m->pid || GetParent(hwnd) != m->top || GetAncestor(hwnd, GA_ROOT) != m->top) return TRUE;
    if (!(GetWindowLongPtrW(hwnd, GWL_STYLE) & WS_CHILD)) return TRUE;
    if (!GetClassNameW(hwnd, name, 128) || wcscmp(name, L"WPEDesktopDX11Window")) return TRUE;
    if (!GetWindowTextW(hwnd, title, 128) || wcscmp(title, L"WPELiveWallpaper")) return TRUE;
    m->children++; m->child = hwnd;
    return TRUE;
}
static BOOL class_is(HWND hwnd, const wchar_t *expected)
{
    wchar_t name[128];
    return GetClassNameW(hwnd, name, 128) > 0 && !wcscmp(name, expected);
}
static BOOL identity_matches(const struct match *m)
{
    DWORD top_pid = 0, child_pid = 0;
    wchar_t title[256], child_title[128];
    return IsWindow(m->top) && IsWindow(m->child)
        && GetWindowThreadProcessId(m->top, &top_pid) && top_pid == m->pid
        && GetWindowThreadProcessId(m->child, &child_pid) && child_pid == m->pid
        && GetAncestor(m->top, GA_ROOT) == m->top && GetParent(m->child) == m->top
        && (GetWindowLongPtrW(m->child, GWL_STYLE) & WS_CHILD)
        && class_is(m->top, L"WPEOverlappedWallpaper") && class_is(m->child, L"WPEDesktopDX11Window")
        && GetWindowTextW(m->top, title, 256) > 0 && !wcscmp(title, m->title)
        && GetWindowTextW(m->child, child_title, 128) > 0 && !wcscmp(child_title, L"WPELiveWallpaper");
}
static BOOL image_matches(DWORD pid, const wchar_t *expected_path)
{
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    wchar_t path[32768], normalized[32768], expected[32768]; DWORD size = 32768;
    if (!process) return FALSE;
    BOOL queried = QueryFullProcessImageNameW(process, 0, path, &size); CloseHandle(process);
    const wchar_t *leaf = queried ? wcsrchr(path, L'\\') : NULL;
    if (!queried || _wcsicmp(leaf ? leaf + 1 : path, L"wallpaper64.exe")) return FALSE;
    if (!expected_path) return TRUE; /* Backward-compatible basename check. */
    /* Optional supervisor-provided absolute Windows path pins this runtime.
     * No basename fallback when an expected full image was provided. */
    if (!((wcslen(expected_path) >= 3 && expected_path[1] == L':'
            && (expected_path[2] == L'\\' || expected_path[2] == L'/'))
            || (expected_path[0] == L'\\' && expected_path[1] == L'\\'))) return FALSE;
    DWORD actual_size = GetFullPathNameW(path, 32768, normalized, NULL);
    DWORD expected_size = GetFullPathNameW(expected_path, 32768, expected, NULL);
    return actual_size && actual_size < 32768 && expected_size && expected_size < 32768
        && !_wcsicmp(normalized, expected);
}
/* Error-only identity evidence: own selected window/process metadata, with
 * UTF-8 JSON escaping. These queries never relax or alter validation. */
static void diagnostic_wide(const wchar_t *text)
{
    if (!text) { fputs("null", stderr); return; }
    int count = WideCharToMultiByte(CP_UTF8, 0, text, -1, NULL, 0, NULL, NULL);
    char *utf8 = count > 0 ? malloc((size_t)count) : NULL;
    if (!utf8 || !WideCharToMultiByte(CP_UTF8, 0, text, -1, utf8, count, NULL, NULL)) {
        free(utf8); fputs("\"<UTF8 conversion unavailable>\"", stderr); return;
    }
    fputc('"', stderr);
    for (const unsigned char *c = (const unsigned char *)utf8; *c; ++c) {
        if (*c == '"' || *c == '\\') { fputc('\\', stderr); fputc(*c, stderr); }
        else if (*c < 32) fprintf(stderr, "\\u%04x", *c);
        else fputc(*c, stderr);
    }
    fputc('"', stderr); free(utf8);
}
static void report_identity_failure(const struct match *m, const wchar_t *expected_image)
{
    wchar_t top_class[128] = {0}, image[32768] = {0}, normalized[32768] = {0}, expected[32768] = {0};
    SetLastError(0); BOOL class_ok = GetClassNameW(m->top, top_class, 128) > 0;
    DWORD class_error = GetLastError();
    SetLastError(0); HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, m->pid);
    DWORD image_error = GetLastError(), size = 32768; BOOL image_ok = FALSE;
    if (process) {
        SetLastError(0); image_ok = QueryFullProcessImageNameW(process, 0, image, &size);
        image_error = GetLastError(); CloseHandle(process);
    }
    DWORD normalized_size = image_ok ? GetFullPathNameW(image, 32768, normalized, NULL) : 0;
    DWORD expected_size = expected_image ? GetFullPathNameW(expected_image, 32768, expected, NULL) : 0;
    fprintf(stderr, "{\"identityFailure\":true,\"topHWND\":\"%p\",\"windowsPID\":%lu,\"topClassOK\":%s,\"topClassError\":%lu,\"actualTopClass\":",
            (void *)m->top, m->pid, class_ok ? "true" : "false", class_error);
    diagnostic_wide(class_ok ? top_class : NULL);
    fputs(",\"expectedTopClass\":\"WPEOverlappedWallpaper\",\"actualImage\":", stderr);
    diagnostic_wide(image_ok ? image : NULL);
    fprintf(stderr, ",\"imageQueryOK\":%s,\"imageQueryError\":%lu,\"expectedImage\":", image_ok ? "true" : "false", image_error);
    diagnostic_wide(expected_image);
    fputs(",\"normalizedActualImage\":", stderr);
    diagnostic_wide(normalized_size && normalized_size < 32768 ? normalized : NULL);
    fputs(",\"normalizedExpectedImage\":", stderr);
    diagnostic_wide(expected_size && expected_size < 32768 ? expected : NULL);
    fputs("}\n", stderr);
}
static BOOL map_child_rect(HWND child, HWND parent, RECT *relative)
{
    if (!GetWindowRect(child, relative)) return FALSE;
    SetLastError(0);
    return MapWindowPoints(NULL, parent, (POINT *)relative, 2) != 0 || GetLastError() == 0;
}
static BOOL fit_renderer(const struct match *m, const wchar_t *expected_image)
{
    RECT parent, window, client, relative;
    if (!identity_matches(m) || !image_matches(m->pid, expected_image)
            || !GetClientRect(m->top, &parent) || !GetWindowRect(m->child, &window)
            || !GetClientRect(m->child, &client)) {
        fputs("Refusing fit: identity/image/rectangle query failed\n", stderr);
        report_identity_failure(m, expected_image); return FALSE;
    }
    int64_t width = (int64_t)parent.right - parent.left, height = (int64_t)parent.bottom - parent.top;
    if (parent.left || parent.top || width <= 0 || height <= 0 || width > INT32_MAX || height > INT32_MAX
            || (int64_t)window.right - window.left != (int64_t)client.right - client.left
            || (int64_t)window.bottom - window.top != (int64_t)client.bottom - client.top
            || !map_child_rect(m->child, m->top, &relative)) {
        fputs("Refusing fit: empty parent, decorated child, or mapping failure\n", stderr); return FALSE;
    }
    if (relative.left == 0 && relative.top == 0 && relative.right == width && relative.bottom == height) return TRUE;
    if (!identity_matches(m) || !image_matches(m->pid, expected_image)) {
        fputs("Refusing fit: identity changed before resize\n", stderr);
        report_identity_failure(m, expected_image); return FALSE;
    }
    /* Use the actual parent client, without fixed pixel offsets, synthesized
     * size messages or changes to the native view/Metal layer. Normal Windows
     * layout/renderer resize notifications remain enabled. */
    if (!SetWindowPos(m->child, NULL, 0, 0, (int)width, (int)height,
            SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER)) {
        fprintf(stderr, "Renderer child fit failed: %lu\n", GetLastError()); return FALSE;
    }
    if (!identity_matches(m) || !GetClientRect(m->top, &parent) || !GetClientRect(m->child, &client)
            || !map_child_rect(m->child, m->top, &relative)
            || parent.left || parent.top || parent.right <= 0 || parent.bottom <= 0
            || relative.left || relative.top || relative.right != parent.right || relative.bottom != parent.bottom
            || client.left || client.top || client.right != parent.right || client.bottom != parent.bottom) {
        fputs("Renderer child fit did not retain current parent bounds\n", stderr); return FALSE;
    }
    return TRUE;
}
static int control_main(int argc, wchar_t **argv)
{
    struct match m = {0};
    DWORD_PTR receiver_result = 0; BOOL paused;
    if ((argc != 4 && argc != 5) || (wcscmp(argv[3], L"pause") && wcscmp(argv[3], L"play")
            && wcscmp(argv[3], L"identify") && wcscmp(argv[3], L"fit"))) {
        fwprintf(stderr, L"Usage: window-playback-control.exe <exact-title> <expected-pid> pause|play|identify|fit [expected-absolute-Windows-image-path]\n");
        return 2;
    }
    wchar_t *end; errno = 0; unsigned long expected = wcstoul(argv[2], &end, 10);
    if (errno || !*argv[1] || end == argv[2] || *end || wcslen(argv[1]) >= 256 || (!expected && wcscmp(argv[3], L"identify"))) { fputs("Invalid title/PID\n", stderr); return 2; }
    m.title = argv[1]; paused = !wcscmp(argv[3], L"pause");
    SetLastError(0);
    if (!EnumWindows(find_top, (LPARAM)&m)) {
        fprintf(stderr,"EnumWindows failed: %lu\n",GetLastError()); return 3;
    }
    if (m.tops != 1 || (expected && m.pid != expected)) {
        fprintf(stderr,"Refusing: exact-title matches=%u actualPID=%lu expectedPID=%lu\n",m.tops,m.pid,expected); return 4;
    }
    const wchar_t *expected_image = argc == 5 ? argv[4] : NULL;
    if (!class_is(m.top, L"WPEOverlappedWallpaper") || !image_matches(m.pid, expected_image)) {
        fprintf(stderr,"Refusing: target class/image does not match this runtime (error=%lu)\n",GetLastError());
        report_identity_failure(&m, expected_image); return 6;
    }
    EnumChildWindows(m.top,find_child,(LPARAM)&m);
    if (m.children != 1) { fprintf(stderr,"Refusing: scene renderer child matches=%u\n",m.children); return 7; }
    if (!wcscmp(argv[3], L"identify")) {
        printf("{\"windowsPID\":%lu}\n", m.pid); return 0;
    }
    if (!fit_renderer(&m, expected_image)) return 9;
    if (!wcscmp(argv[3], L"fit")) {
        printf("fit pid=%lu top=%p renderer=%p\n", m.pid, (void *)m.top, (void *)m.child); return 0;
    }
    if (!identity_matches(&m) || !image_matches(m.pid, expected_image)) {
        fputs("Refusing control: target identity changed\n", stderr);
        report_identity_failure(&m, expected_image); return 9;
    }
    /* Original scene vtable+0x28 sends msg0x40b bool in WPARAM, LPARAM0.
     * Do not send to the unrelated main singleton/outer pop-out HWND. */
    SetLastError(0);
    if (!SendMessageTimeoutW(m.child,0x40b,paused,0,SMTO_ABORTIFHUNG|SMTO_BLOCK,2000,&receiver_result)) {
        fprintf(stderr,"Pause message delivery failed: error=%lu\n",GetLastError()); return 8;
    }
    printf("delivered pid=%lu top=%p renderer=%p msg=0x40b paused=%u receiver_result=%llu\n",
           m.pid,(void *)m.top,(void *)m.child,(unsigned)paused,(unsigned long long)receiver_result);
    return 0;
}

/* GUI subsystem prevents Wine allocating a console window. Standard handles are
 * inherited from the supervisor's redirected NSTask; no window is created. */
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR command, int show)
{
    (void)instance; (void)previous; (void)command; (void)show;
    int argc = 0; wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) { fprintf(stderr, "Command line parse failed: %lu\n", GetLastError()); return 2; }
    int result = control_main(argc, argv); LocalFree(argv); return result;
}
