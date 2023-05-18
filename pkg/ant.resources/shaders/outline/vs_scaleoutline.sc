#include "common/inputs.sh"

$input 	a_position INPUT_NORMAL INPUT_TANGENT

#include <bgfx_shader.sh>

#include "common/transform.sh"

uniform vec4 u_outlinescale;
#define u_outline_width u_outlinescale.x

void main()
{
#	if PACK_TANGENT_TO_QUAT
	mediump vec3 normal = quat_to_normal(a_tangent);
#	else //!PACK_TANGENT_TO_QUAT
	mediump vec3 normal = a_normal;
#	endif//PACK_TANGENT_TO_QUAT

#ifdef VIEW_SPACE
    vec4 pos = mul(u_modelView, vec4(a_position, 1.0));
    // normal should be transformed corredctly by transpose of inverse modelview matrix when anti-uniform scaled
    normal	= normalize(mul(u_modelView, mediump vec4(normal, 0.0)).xyz);
    normal.z = -2;
    pos = pos + vec4(normal, 0) * u_outline_width;
    gl_Position = mul(u_proj, pos); 
#else // SCREEN_SPACE
    vec2 screen_normal = mul(u_modelViewProj, vec4(a_normal, 0.0)).xy;
    screen_normal = normalize(screen_normal);

    //make x direction offset same as y direction
    float w = u_viewRect.z;
    float h = u_viewRect.w;
    screen_normal.x *= h / w;

    // offset posision in clip space
    float zoffset = 0.01;
    vec4 clipPos = mul(u_modelViewProj, vec4(a_position, 1.0));
    gl_Position = clipPos;
    gl_Position.xyz += vec3(screen_normal * u_outline_width, zoffset) * clipPos.w;
#endif //VIEW_SPACE
}