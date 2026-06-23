/*
 * aicoder - C + Lua glue layer
 * Minimal: embeds Lua, spawns processes, file I/O
 */

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <errno.h>

/* --- Process spawning --- */

static int l_spawn(lua_State *L) {
    const char *cmd = luaL_checkstring(L, 1);
    FILE *fp = popen(cmd, "r");
    if (!fp) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    /* Read output into buffer */
    size_t bufsize = 65536;
    char *output = malloc(bufsize);
    size_t total = 0;
    char buf[4096];

    while (fgets(buf, sizeof(buf), fp) && total < bufsize - 4096) {
        size_t len = strlen(buf);
        memcpy(output + total, buf, len);
        total += len;
    }
    output[total] = '\0';

    int status = pclose(fp);

    lua_newtable(L);
    lua_pushstring(L, "output");
    lua_pushstring(L, output);
    lua_settable(L, -3);
    lua_pushstring(L, "status");
    lua_pushinteger(L, status);
    lua_settable(L, -3);

    free(output);
    return 1;
}

/* --- File I/O --- */

static int l_read_file(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    FILE *fp = fopen(path, "r");
    if (!fp) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }

    fseek(fp, 0, SEEK_END);
    long len = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    char *content = malloc(len + 1);
    fread(content, 1, len, fp);
    content[len] = '\0';
    fclose(fp);

    lua_pushstring(L, content);
    free(content);
    return 1;
}

static int l_write_file(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    const char *content = luaL_checkstring(L, 2);
    FILE *fp = fopen(path, "w");
    if (!fp) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, strerror(errno));
        return 2;
    }
    fputs(content, fp);
    fclose(fp);
    lua_pushboolean(L, 1);
    return 1;
}

/* --- Get env var --- */

static int l_getenv(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    const char *val = getenv(name);
    if (val) {
        lua_pushstring(L, val);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

/* --- Sleep --- */

static int l_sleep_ms(lua_State *L) {
    int ms = (int)luaL_checkinteger(L, 1);
    usleep(ms * 1000);
    return 0;
}

/* --- Register C functions to Lua --- */

static const struct luaL_Reg cfuncs[] = {
    {"spawn", l_spawn},
    {"read_file", l_read_file},
    {"write_file", l_write_file},
    {"getenv", l_getenv},
    {"sleep_ms", l_sleep_ms},
    {NULL, NULL}
};

/* --- Signal handling --- */

volatile sig_atomic_t got_sigint = 0;

void sigint_handler(int sig) {
    (void)sig;
    got_sigint = 1;
}

/* --- Main --- */

int main(int argc, char **argv) {
    const char *script_path = "main.lua";

    if (argc > 1) {
        script_path = argv[1];
    }

    /* Setup signal handler */
    signal(SIGINT, sigint_handler);

    /* Create Lua state */
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);

    /* Register C functions */
    luaL_newlib(L, cfuncs);
    lua_setglobal(L, "c");

    /* Store sigint flag in Lua global for scripts to check */
    lua_pushboolean(L, 0);
    lua_setglobal(L, "SIGINT");

    /* Execute main.lua */
    if (luaL_dofile(L, script_path) != 0) {
        fprintf(stderr, "Lua error: %s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}