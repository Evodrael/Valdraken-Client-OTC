uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;

void main()
{
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    if (color.a < 0.01) discard;

    float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));

    float wave = sin(v_TexCoord.x * 10.0 + u_Time * 2.0) * 0.1 
               + sin(v_TexCoord.y * 15.0 - u_Time * 5.0) * 0.4;
    
    float intensity = clamp(luminance + wave, 0.0, 1.0);

    // Cores: Quase preto no fundo, Vermelho Vinho (mais fechado) nas chamas
    vec3 darkColor = vec3(0.05, 0.0, 0.0);
    vec3 lightColor = vec3(0.5, 0.0, 0.15);

    vec3 finalColor = mix(darkColor, lightColor, intensity);

    gl_FragColor = vec4(finalColor, color.a * 0.9);
}