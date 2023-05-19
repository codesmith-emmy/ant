#include <lua.hpp>
#include "window.h"
#include "../../window.h"

template <typename T>
void push_value(lua_State* L, T v);

template <>
void push_value<NSString*>(lua_State* L, NSString* v) {
    lua_pushstring(L, [v UTF8String]);
}

template <>
void push_value<UIGestureRecognizerState>(lua_State* L, UIGestureRecognizerState v) {
    switch (v) {
    case UIGestureRecognizerStatePossible:
        lua_pushstring(L, "possible");
        break;
    case UIGestureRecognizerStateBegan:
        lua_pushstring(L, "began");
        break;
    case UIGestureRecognizerStateChanged:
        lua_pushstring(L, "changed");
        break;
    case UIGestureRecognizerStateEnded:
        lua_pushstring(L, "ended");
        break;
    case UIGestureRecognizerStateCancelled:
        lua_pushstring(L, "cancelled");
        break;
    case UIGestureRecognizerStateFailed:
        lua_pushstring(L, "failed");
        break;
    default:
        lua_pushstring(L, "unknown");
        break;
    }
}

template <>
void push_value<UISwipeGestureRecognizerDirection>(lua_State* L, UISwipeGestureRecognizerDirection v) {
    lua_pushinteger(L, v);
}

template <>
void push_value<CGPoint>(lua_State* L, CGPoint v) {
    lua_createtable(L, 0, 2);
    lua_pushnumber(L, static_cast<lua_Number>(v.x));
    lua_setfield(L, -2, "x");
    lua_pushnumber(L, static_cast<lua_Number>(v.y));
    lua_setfield(L, -2, "y");
}

template <typename T>
    requires (std::is_floating_point_v<T>)
void push_value(lua_State* L, T v) {
    lua_pushnumber(L, static_cast<lua_Number>(v));
}

static NSString* lua_getnsstring(lua_State* L, int idx, const char* field, NSString* def) {
    if (LUA_TSTRING != lua_getfield(L, idx, field)) {
        lua_pop(L, 1);
        return def;
    }
    NSString* r = [NSString stringWithUTF8String:lua_tostring(L, -1)];
    lua_pop(L, 1);
    return r;
}

template <typename T>
    requires (std::is_integral_v<T>)
void set_arg(lua_State* L, const char* field, std::function<void(T)> func) {
    if (LUA_TNUMBER != lua_getfield(L, 1, field)) {
        lua_pop(L, 1);
        return;
    }
    if (!lua_isinteger(L, -1)) {
        lua_pop(L, 1);
        return;
    }
    lua_Integer r = lua_tointeger(L, -1);
    lua_pop(L, 1);
    func(static_cast<T>(r));
}

template <typename T>
    requires (std::is_floating_point_v<T>)
void set_arg(lua_State* L, const char* field, std::function<void(T)> func) {
    if (LUA_TNUMBER != lua_getfield(L, 1, field)) {
        lua_pop(L, 1);
        return;
    }
    lua_Number r = lua_tonumber(L, -1);
    lua_pop(L, 1);
    func(static_cast<T>(r));
}

static void add_gesture(UIGestureRecognizer* gesture) {
    CFRunLoopPerformBlock([[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopCommonModes,
    ^{
        [global_window addGestureRecognizer:gesture];
    });
}

static void remove_gesture(UIGestureRecognizer* gesture) {
    CFRunLoopPerformBlock([[NSRunLoop mainRunLoop] getCFRunLoop], kCFRunLoopCommonModes,
    ^{
        [global_window removeGestureRecognizer:gesture];
    });
}

@interface LuaTapGesture : UITapGestureRecognizer {
    NSString* name;
}
@end
@implementation LuaTapGesture
@end

@interface LuaLongPressGesture : UILongPressGestureRecognizer {
    NSString* name;
}
@end
@implementation LuaLongPressGesture
@end

@interface LuaPinchGesture : UIPinchGestureRecognizer {
    NSString* name;
}
@end
@implementation LuaPinchGesture
@end

@interface LuaSwipeGesture : UISwipeGestureRecognizer {
    NSString* name;
}
@end
@implementation LuaSwipeGesture
@end

@interface LuaPanGesture : UIPanGestureRecognizer {
    NSString* name;
}
@end
@implementation LuaPanGesture
@end

static void setState(lua_State* L, int idx, UIGestureRecognizer* gesture) {
    push_value(L, gesture.state);
    lua_setfield(L, idx, "state");
}

static void setLocationInView(lua_State* L, int idx, UIGestureRecognizer* gesture) {
    CGPoint pt = [gesture locationInView:global_window];
    pt.x *= global_window.contentScaleFactor;
    pt.y *= global_window.contentScaleFactor;
    push_value(L, pt);
    lua_setfield(L, idx, "locationInView");
}

static void setLocationOfTouch(lua_State* L, int idx, UIGestureRecognizer* gesture) {
    NSUInteger n = gesture.numberOfTouches;
    lua_createtable(L, static_cast<int>(n), 0);
    for (NSUInteger i = 0; i < n; ++i) {
        CGPoint pt = [gesture locationOfTouch:i inView:global_window];
        pt.x *= global_window.contentScaleFactor;
        pt.y *= global_window.contentScaleFactor;
        push_value(L, pt);
        lua_seti(L, -2, static_cast<lua_Integer>(i + 1));
    }
    lua_setfield(L, idx, "locationOfTouch");
}

static void setTranslationInView(lua_State* L, int idx, UIPanGestureRecognizer* gesture) {
    CGPoint pt = [gesture translationInView:global_window];
    push_value(L, pt);
    lua_setfield(L, idx, "translationInView");
}

static void setVelocityInView(lua_State* L, int idx, UIPanGestureRecognizer* gesture) {
    CGPoint pt = [gesture velocityInView:global_window];
    push_value(L, pt);
    lua_setfield(L, idx, "velocityInView");
}

@interface LuaGestureHandler : NSObject {
}
@end
@implementation LuaGestureHandler
-(void)handleTap:(LuaTapGesture *)gesture {
    window_message(g_cb, [&](lua_State* L) {
        lua_pushstring(L, "gesture");
        push_value(L, [gesture name]);
        lua_newtable(L);
        setLocationInView(L, 4, gesture);
        setLocationOfTouch(L, 4, gesture);
    });
}
-(void)handleLongPress:(LuaLongPressGesture *)gesture {
    window_message(g_cb, [&](lua_State* L) {
        lua_pushstring(L, "gesture");
        push_value(L, [gesture name]);
        lua_newtable(L);
        setState(L, 4, gesture);
        setLocationInView(L, 4, gesture);
        setLocationOfTouch(L, 4, gesture);
    });
}
-(void)handlePinch:(LuaPinchGesture *)gesture {
    window_message(g_cb, [&](lua_State* L) {
        lua_pushstring(L, "gesture");
        push_value(L, [gesture name]);
        lua_newtable(L);
        setState(L, 4, gesture);
        setLocationInView(L, 4, gesture);
        setLocationOfTouch(L, 4, gesture);
        push_value(L, gesture.scale);
        lua_setfield(L, 4, "scale");
        push_value(L, gesture.velocity);
        lua_setfield(L, 4, "velocity");
    });
}
-(void)handleSwipe:(LuaSwipeGesture *)gesture {
    window_message(g_cb, [&](lua_State* L) {
        lua_pushstring(L, "gesture");
        push_value(L, [gesture name]);
        lua_newtable(L);
        setLocationInView(L, 4, gesture);
        setLocationOfTouch(L, 4, gesture);
        push_value(L, gesture.direction);
        lua_setfield(L, 4, "direction");
    });
}
-(void)handlePan:(LuaPanGesture *)gesture {
    window_message(g_cb, [&](lua_State* L) {
        lua_pushstring(L, "gesture");
        push_value(L, [gesture name]);
        lua_newtable(L);
        setState(L, 4, gesture);
        setLocationInView(L, 4, gesture);
        setLocationOfTouch(L, 4, gesture);
        setTranslationInView(L, 4, gesture);
        setVelocityInView(L, 4, gesture);
    });
}
@end

static int ltap(lua_State* L) {
    if (!global_window) {
        return luaL_error(L, "window not initialized.");
    }
    luaL_checktype(L, 1, LUA_TTABLE);
    id handler = (__bridge id)lua_touserdata(L, lua_upvalueindex(1));
    LuaTapGesture* gesture = [[LuaTapGesture alloc] initWithTarget:handler action:@selector(handleTap:)];
    gesture.name = lua_getnsstring(L, 1, "name", @"tap");
    set_arg<NSUInteger>(L, "numberOfTapsRequired", [&](auto v){
        gesture.numberOfTapsRequired = v;
    });
    set_arg<NSUInteger>(L, "numberOfTouchesRequired", [&](auto v){
        gesture.numberOfTouchesRequired = v;
    });
    add_gesture(gesture);
    lua_pushlightuserdata(L, (__bridge_retained void*)gesture);
    return 1;
}

static int llong_press(lua_State* L) {
    if (!global_window) {
        return luaL_error(L, "window not initialized.");
    }
    luaL_checktype(L, 1, LUA_TTABLE);
    id handler = (__bridge id)lua_touserdata(L, lua_upvalueindex(1));
    LuaLongPressGesture* gesture = [[LuaLongPressGesture alloc] initWithTarget:handler action:@selector(handleLongPress:)];
    gesture.name = lua_getnsstring(L, 1, "name", @"long_press");
    set_arg<NSUInteger>(L, "numberOfTapsRequired", [&](auto v){
        gesture.numberOfTapsRequired = v;
    });
    set_arg<NSUInteger>(L, "numberOfTouchesRequired", [&](auto v){
        gesture.numberOfTouchesRequired = v;
    });
    set_arg<NSTimeInterval>(L, "minimumPressDuration", [&](auto v){
        gesture.minimumPressDuration = v;
    });
    set_arg<CGFloat>(L, "allowableMovement", [&](auto v){
        gesture.allowableMovement = v;
    });
    add_gesture(gesture);
    lua_pushlightuserdata(L, (__bridge_retained void*)gesture);
    return 1;
}

static int lpinch(lua_State* L) {
    if (!global_window) {
        return luaL_error(L, "window not initialized.");
    }
    luaL_checktype(L, 1, LUA_TTABLE);
    id handler = (__bridge id)lua_touserdata(L, lua_upvalueindex(1));
    LuaPinchGesture* gesture = [[LuaPinchGesture alloc] initWithTarget:handler action:@selector(handlePinch:)];
    gesture.name = lua_getnsstring(L, 1, "name", @"pinch");
    add_gesture(gesture);
    lua_pushlightuserdata(L, (__bridge_retained void*)gesture);
    return 1;
}

static int lswipe(lua_State* L) {
    if (!global_window) {
        return luaL_error(L, "window not initialized.");
    }
    luaL_checktype(L, 1, LUA_TTABLE);
    id handler = (__bridge id)lua_touserdata(L, lua_upvalueindex(1));
    LuaSwipeGesture* gesture = [[LuaSwipeGesture alloc] initWithTarget:handler action:@selector(handleSwipe:)];
    gesture.name = lua_getnsstring(L, 1, "name", @"swipe");
    set_arg<NSUInteger>(L, "numberOfTouchesRequired", [&](auto v){
        gesture.numberOfTouchesRequired = v;
    });
    set_arg<UISwipeGestureRecognizerDirection>(L, "direction", [&](auto v){
        gesture.direction = v;
    });
    add_gesture(gesture);
    lua_pushlightuserdata(L, (__bridge_retained void*)gesture);
    return 1;
}

static int lpan(lua_State* L) {
    if (!global_window) {
        return luaL_error(L, "window not initialized.");
    }
    luaL_checktype(L, 1, LUA_TTABLE);
    id handler = (__bridge id)lua_touserdata(L, lua_upvalueindex(1));
    LuaPanGesture* gesture = [[LuaPanGesture alloc] initWithTarget:handler action:@selector(handlePan:)];
    gesture.name = lua_getnsstring(L, 1, "name", @"pan");
    set_arg<NSUInteger>(L, "maximumNumberOfTouches", [&](auto v){
        gesture.maximumNumberOfTouches = v;
    });
    set_arg<NSUInteger>(L, "minimumNumberOfTouches", [&](auto v){
        gesture.minimumNumberOfTouches = v;
    });
    add_gesture(gesture);
    lua_pushlightuserdata(L, (__bridge_retained void*)gesture);
    return 1;
}

static int lremove(lua_State* L) {
    if (!global_window) {
        return luaL_error(L, "window not initialized.");
    }
    luaL_checktype(L, 1, LUA_TLIGHTUSERDATA);
    UIGestureRecognizer* gesture = (__bridge_transfer UIGestureRecognizer*)lua_touserdata(L, 1);
    remove_gesture(gesture);
    return 0;
}

static int lrequireToFail(lua_State* L) {
    luaL_checktype(L, 1, LUA_TLIGHTUSERDATA);
    luaL_checktype(L, 2, LUA_TLIGHTUSERDATA);
    UIGestureRecognizer* a = (__bridge UIGestureRecognizer*)lua_touserdata(L, 1);
    UIGestureRecognizer* b = (__bridge UIGestureRecognizer*)lua_touserdata(L, 2);
    [a requireGestureRecognizerToFail:b];
    return 0;
}

extern "C"
int luaopen_ios_gesture(lua_State* L) {
    luaL_checkversion(L);
    luaL_Reg l[] = {
        { "tap", ltap },
        { "long_press", llong_press },
        { "pinch", lpinch },
        { "swipe", lswipe },
        { "pan", lpan },
        { "remove", lremove },
        { "requireToFail", lrequireToFail },
        { NULL, NULL },
    };
    luaL_newlibtable(L, l);
    LuaGestureHandler* handler = [[LuaGestureHandler alloc] init];
    lua_pushlightuserdata(L, (__bridge_retained void*)handler);
    luaL_setfuncs(L, l, 1);
    return 1;
}
