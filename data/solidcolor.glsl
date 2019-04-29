uniform sampler2D ColorTexture; 
uniform vec4 ColorRGB; 

void shader() { 
    vec4 color = texture2D(ColorTexture, b3d_Texcoord0);
    color.a *= ColorRGB.a;
    b3d_FragColor = vec4(ColorRGB.rgb * color.a, color.a);
}
