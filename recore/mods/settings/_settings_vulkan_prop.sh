# ==============================================================================
#
# MOD_NAME="ReCoreUI Settings - Vulkan Renderer Toggle"
# MOD_AUTHOR="salvogiangri (ported from UN1CA)"
# MOD_DESC="Seeds persist.sys.unica.vulkan=false on devices that don't already
#           default to the Vulkan (skiavk) renderer, so the 'Enable Vulkan
#           renderer' toggle added by this Settings mod starts in a known,
#           off state instead of reading as unset."
#
# ==============================================================================
#
# Ported from UN1CA's customize.sh:
#   if [[ "$(GET_PROP "ro.hwui.use_vulkan")" != "true" ]]; then
#       SET_PROP "system" "persist.sys.unica.vulkan" "false"
#   fi
#
# GET_PROP requires a partition argument in ReCoreUI; SET_PROP has no direct
# equivalent, BPROP is ReCoreUI's build.prop setter (see mods/spoofing/spoof.sh,
# mods/multiuser/... for other examples of this exact pattern).
#
# See also: system.img/etc/init/vulkan.rc in this same mod folder, which reads
# this same property at boot to switch the renderer.

if [[ "$(GET_PROP "system" "ro.hwui.use_vulkan")" != "true" ]]; then
    BPROP "system" "persist.sys.unica.vulkan" "false"
fi
