// UnRAR source code may be used in any software to handle RAR archives without
// limitations free of charge, but cannot be used to develop RAR (WinRAR)
// compatible archiver and to re-create RAR compression algorithm, which is
// proprietary. Distribution of modified UnRAR source code in separate form or
// as a part of other software is permitted, provided that full text of this
// paragraph, starting from "UnRAR source code" words, is included in license,
// or in documentation if license is not available, and in source code comments
// of resulting package.
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <string>
#include <locale>
#include <codecvt>
#include "unrar/dll.hpp"

using Begin = int (*)(void *, const char *, int, int64_t);
using Data = int (*)(void *, const void *, int);
using End = int (*)(void *);
struct Context {
    void *user; Data data; const char *password;
    bool requested = false;
};
static int callback(UINT message, LPARAM user, LPARAM p1, LPARAM p2) {
    auto &c = *reinterpret_cast<Context *>(user);
    if (message == UCM_PROCESSDATA)
        return c.data(c.user, reinterpret_cast<void *>(p1), int(p2)) ? 1 : -1;
    if (message == UCM_CHANGEVOLUME || message == UCM_CHANGEVOLUMEW) return -1;
    if (message == UCM_LARGEDICT) return -1;
    if (message == UCM_NEEDPASSWORD || message == UCM_NEEDPASSWORDW) {
        c.requested = true;
        if (!c.password || !*c.password || p2 <= 0) return -1;
        if (message == UCM_NEEDPASSWORD) {
            if (strlen(c.password) >= size_t(p2)) return -1;
            strcpy(reinterpret_cast<char *>(p1), c.password);
        } else {
            try {
                auto wide = std::wstring_convert<std::codecvt_utf8<wchar_t>>().from_bytes(c.password);
                if (wide.size() >= size_t(p2)) return -1;
                wcscpy(reinterpret_cast<wchar_t *>(p1), wide.c_str());
            } catch (...) { return -1; }
        }
        return 1;
    }
    return 1;
}

// Never let UnRAR write archive paths: stream RAR_TEST bytes to Swift's safe
// staging writer. No password in argv, environment, log files or subprocesses.
extern "C" int orbit_unrar_walk(const char *path, const char *password,
                               Begin begin, Data data, End end, void *user) {
    Context context;
    context.user = user; context.data = data; context.password = password;
    RAROpenArchiveDataEx open{};
    open.ArcName = const_cast<char *>(path); open.OpenMode = RAR_OM_EXTRACT;
    open.Callback = callback; open.UserData = reinterpret_cast<LPARAM>(&context);
    HANDLE archive = RAROpenArchiveEx(&open);
    if (!archive) {
        if (context.requested && (!password || !*password)) return ERAR_MISSING_PASSWORD;
        if (context.requested && open.OpenResult == ERAR_BAD_DATA) return ERAR_BAD_PASSWORD;
        return int(open.OpenResult);
    }
    struct Close { HANDLE h; ~Close() { RARCloseArchive(h); } } closer{archive};
    for (;;) {
        RARHeaderDataEx h{};
        int status = RARReadHeaderEx(archive, &h);
        if (status == ERAR_END_ARCHIVE) return 0;
        if (status) {
            if (context.requested && (!password || !*password)) return ERAR_MISSING_PASSWORD;
            if (context.requested && status == ERAR_BAD_DATA) return ERAR_BAD_PASSWORD;
            return status;
        }
        if (h.Flags & (RHDF_SPLITBEFORE | RHDF_SPLITAFTER)) return 102;
        if (h.RedirType != 0 || (h.HostOS == 3 && (h.FileAttr & 0170000) != 0100000 && (h.FileAttr & 0170000) != 0040000)) return 103;
        if (h.DictSize > 512*1024) return ERAR_LARGE_DICT;
        bool directory = (h.Flags & RHDF_DIRECTORY) != 0;
        uint64_t size = (uint64_t(h.UnpSizeHigh) << 32) | h.UnpSize;
        if (size > 512000000) return 104;
        std::string name;
        try { name = std::wstring_convert<std::codecvt_utf8<wchar_t>>().to_bytes(h.FileNameW); }
        catch (...) { return ERAR_BAD_DATA; }
        if (name.empty() || !begin(user, name.c_str(), directory, int64_t(size))) return 105;
        status = RARProcessFile(archive, directory ? RAR_SKIP : RAR_TEST, nullptr, nullptr);
        if (status) {
            if (context.requested && (!password || !*password)) return ERAR_MISSING_PASSWORD;
            if (status == ERAR_BAD_DATA && (h.Flags & RHDF_ENCRYPTED)) return ERAR_BAD_PASSWORD;
            return status;
        }
        if (!end(user)) return 105;
    }
}
