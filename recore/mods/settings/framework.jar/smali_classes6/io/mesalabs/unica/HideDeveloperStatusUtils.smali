.class public final Lio/mesalabs/unica/HideDeveloperStatusUtils;
.super Ljava/lang/Object;
.source "HideDeveloperStatusUtils.java"


# annotations
.annotation system Ldalvik/annotation/MemberClasses;
    value = {
        Lio/mesalabs/unica/HideDeveloperStatusUtils$Action;
    }
.end annotation


# static fields
.field private static final blacklist settingsToHide:Ljava/util/Set;
    .annotation system Ldalvik/annotation/Signature;
        value = {
            "Ljava/util/Set<",
            "Ljava/lang/String;",
            ">;"
        }
    .end annotation
.end field


# direct methods
.method static constructor blacklist <clinit>()V
    .locals 4

    new-instance v0, Ljava/util/HashSet;

    const/4 v1, 0x3

    new-array v1, v1, [Ljava/lang/String;

    const/4 v2, 0x0

    const-string v3, "adb_enabled"

    aput-object v3, v1, v2

    const/4 v2, 0x1

    const-string v3, "adb_wifi_enabled"

    aput-object v3, v1, v2

    const/4 v2, 0x2

    const-string v3, "development_settings_enabled"

    aput-object v3, v1, v2

    invoke-static {v1}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object v1

    invoke-direct {v0, v1}, Ljava/util/HashSet;-><init>(Ljava/util/Collection;)V

    sput-object v0, Lio/mesalabs/unica/HideDeveloperStatusUtils;->settingsToHide:Ljava/util/Set;

    return-void
.end method

.method public constructor blacklist <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static blacklist getApps(Landroid/content/ContentResolver;)Ljava/util/Set;
    .locals 2
    .annotation system Ldalvik/annotation/Signature;
        value = {
            "(",
            "Landroid/content/ContentResolver;",
            ")",
            "Ljava/util/Set<",
            "Ljava/lang/String;",
            ">;"
        }
    .end annotation

    if-nez p0, :cond_0

    new-instance p0, Ljava/util/HashSet;

    invoke-direct {p0}, Ljava/util/HashSet;-><init>()V

    return-object p0

    :cond_0
    const-string/jumbo v0, "unica_hide_dev_list"

    invoke-static {p0, v0}, Landroid/provider/Settings$Secure;->getString(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/String;

    move-result-object p0

    if-eqz p0, :cond_1

    invoke-virtual {p0}, Ljava/lang/String;->isEmpty()Z

    move-result v0

    if-nez v0, :cond_1

    const-string v0, ","

    invoke-virtual {p0, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v1

    if-nez v1, :cond_1

    new-instance v1, Ljava/util/HashSet;

    invoke-virtual {p0, v0}, Ljava/lang/String;->split(Ljava/lang/String;)[Ljava/lang/String;

    move-result-object p0

    invoke-static {p0}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;

    move-result-object p0

    invoke-direct {v1, p0}, Ljava/util/HashSet;-><init>(Ljava/util/Collection;)V

    return-object v1

    :cond_1
    new-instance p0, Ljava/util/HashSet;

    invoke-direct {p0}, Ljava/util/HashSet;-><init>()V

    return-object p0
.end method

.method public static blacklist getApps(Landroid/content/Context;)Ljava/util/Set;
    .locals 0
    .annotation system Ldalvik/annotation/Signature;
        value = {
            "(",
            "Landroid/content/Context;",
            ")",
            "Ljava/util/Set<",
            "Ljava/lang/String;",
            ">;"
        }
    .end annotation

    if-nez p0, :cond_0

    new-instance p0, Ljava/util/HashSet;

    invoke-direct {p0}, Ljava/util/HashSet;-><init>()V

    return-object p0

    :cond_0
    invoke-virtual {p0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object p0

    invoke-static {p0}, Lio/mesalabs/unica/HideDeveloperStatusUtils;->getApps(Landroid/content/ContentResolver;)Ljava/util/Set;

    move-result-object p0

    return-object p0
.end method

.method private static blacklist isBootCompleted()Z
    .locals 2

    const-string/jumbo v0, "sys.boot_completed"

    const/4 v1, 0x0

    invoke-static {v0, v1}, Landroid/os/SemSystemProperties;->getBoolean(Ljava/lang/String;Z)Z

    move-result v0

    return v0
.end method

.method private static blacklist putAppsForUser(Landroid/content/Context;Ljava/lang/String;ILio/mesalabs/unica/HideDeveloperStatusUtils$Action;)V
    .locals 2

    if-eqz p0, :cond_3

    if-gez p2, :cond_0

    goto :goto_1

    :cond_0
    invoke-static {p0}, Lio/mesalabs/unica/HideDeveloperStatusUtils;->getApps(Landroid/content/Context;)Ljava/util/Set;

    move-result-object v0

    invoke-virtual {p3}, Lio/mesalabs/unica/HideDeveloperStatusUtils$Action;->ordinal()I

    move-result p3

    if-eqz p3, :cond_2

    const/4 v1, 0x1

    if-eq p3, v1, :cond_1

    goto :goto_0

    :cond_1
    invoke-interface {v0, p1}, Ljava/util/Set;->remove(Ljava/lang/Object;)Z

    goto :goto_0

    :cond_2
    invoke-interface {v0, p1}, Ljava/util/Set;->add(Ljava/lang/Object;)Z

    :goto_0
    invoke-virtual {p0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object p0

    const-string p1, ","

    invoke-static {p1, v0}, Ljava/lang/String;->join(Ljava/lang/CharSequence;Ljava/lang/Iterable;)Ljava/lang/String;

    move-result-object p1

    const-string/jumbo p3, "unica_hide_dev_list"

    invoke-static {p0, p3, p1, p2}, Landroid/provider/Settings$Secure;->putStringForUser(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;I)Z

    :cond_3
    :goto_1
    return-void
.end method

.method public static blacklist shouldHideDevStatus(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z
    .locals 3

    const/4 v0, 0x0

    if-eqz p0, :cond_4

    if-eqz p1, :cond_4

    if-eqz p2, :cond_4

    invoke-static {}, Lio/mesalabs/unica/HideDeveloperStatusUtils;->isBootCompleted()Z

    move-result v1

    if-nez v1, :cond_0

    goto :goto_0

    :cond_0
    const-string/jumbo v1, "unica_hide_dev"

    const/4 v2, 0x1

    invoke-static {p0, v1, v2}, Landroid/provider/Settings$System;->getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I

    move-result v1

    if-eq v1, v2, :cond_1

    return v0

    :cond_1
    sget-object v1, Lio/mesalabs/unica/HideDeveloperStatusUtils;->settingsToHide:Ljava/util/Set;

    invoke-interface {v1, p2}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z

    move-result p2

    if-nez p2, :cond_2

    return v0

    :cond_2
    invoke-static {p0}, Lio/mesalabs/unica/HideDeveloperStatusUtils;->getApps(Landroid/content/ContentResolver;)Ljava/util/Set;

    move-result-object p0

    invoke-interface {p0}, Ljava/util/Set;->isEmpty()Z

    move-result p2

    if-eqz p2, :cond_3

    return v0

    :cond_3
    invoke-interface {p0, p1}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z

    move-result p0

    return p0

    :cond_4
    :goto_0
    return v0
.end method


# virtual methods
.method public blacklist addApp(Landroid/content/Context;Ljava/lang/String;I)V
    .locals 0

    if-eqz p1, :cond_1

    if-eqz p2, :cond_1

    if-gez p3, :cond_0

    goto :goto_0

    :cond_0
    sget-object p0, Lio/mesalabs/unica/HideDeveloperStatusUtils$Action;->ADD:Lio/mesalabs/unica/HideDeveloperStatusUtils$Action;

    invoke-static {p1, p2, p3, p0}, Lio/mesalabs/unica/HideDeveloperStatusUtils;->putAppsForUser(Landroid/content/Context;Ljava/lang/String;ILio/mesalabs/unica/HideDeveloperStatusUtils$Action;)V

    :cond_1
    :goto_0
    return-void
.end method

.method public blacklist removeApp(Landroid/content/Context;Ljava/lang/String;I)V
    .locals 0

    if-eqz p1, :cond_1

    if-eqz p2, :cond_1

    if-gez p3, :cond_0

    goto :goto_0

    :cond_0
    sget-object p0, Lio/mesalabs/unica/HideDeveloperStatusUtils$Action;->REMOVE:Lio/mesalabs/unica/HideDeveloperStatusUtils$Action;

    invoke-static {p1, p2, p3, p0}, Lio/mesalabs/unica/HideDeveloperStatusUtils;->putAppsForUser(Landroid/content/Context;Ljava/lang/String;ILio/mesalabs/unica/HideDeveloperStatusUtils$Action;)V

    :cond_1
    :goto_0
    return-void
.end method

.method public blacklist setApps(Landroid/content/Context;I)V
    .locals 1

    if-eqz p1, :cond_1

    if-gez p2, :cond_0

    goto :goto_0

    :cond_0
    const/4 p0, 0x0

    sget-object v0, Lio/mesalabs/unica/HideDeveloperStatusUtils$Action;->SET:Lio/mesalabs/unica/HideDeveloperStatusUtils$Action;

    invoke-static {p1, p0, p2, v0}, Lio/mesalabs/unica/HideDeveloperStatusUtils;->putAppsForUser(Landroid/content/Context;Ljava/lang/String;ILio/mesalabs/unica/HideDeveloperStatusUtils$Action;)V

    :cond_1
    :goto_0
    return-void
.end method
