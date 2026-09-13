#version 300 es
precision mediump float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);

    // Black & white: perceived brightness (Rec. 709 luma weights -- green
    // looks brightest to the eye, blue darkest), so the image keeps its
    // natural contrast instead of the flat look of a plain RGB average.
    float luma = dot(pixColor.rgb, vec3(0.2126, 0.7152, 0.0722));

    fragColor = vec4(vec3(luma), pixColor.a);
}
