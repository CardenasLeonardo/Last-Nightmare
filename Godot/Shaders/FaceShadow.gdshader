shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, diffuse_lambert, specular_schlick_ggx;

// Tapa la parte de arriba del cuerpo (cara/cráneo, tapada en su mayoría por
// el pelo toon) con una "niebla" negra densa y en movimiento en vez de un
// color plano: varias capas de ruido (fbm), desplazadas con el tiempo a
// distinta velocidad/escala, generan remolinos de humo que nunca se quedan
// quietos. El corte sigue siendo por altura local (VERTEX.y, ya con el
// esqueleto aplicado) con degradado suave + fresnel en el borde, igual que
// antes; lo que cambia es que adentro de esa zona ya no es un color sólido.

uniform sampler2D _albedo_tex: source_color, hint_default_white;
uniform vec3 _body_color: source_color = vec3(1.0, 1.0, 1.0); // tiñe la piel/cuerpo (zona sin niebla)
uniform vec3 _shadow_color: source_color = vec3(0.02, 0.02, 0.03);
uniform vec3 _fog_color: source_color = vec3(0.0, 0.0, 0.0); // negro puro de las zonas más densas del humo
uniform float _threshold_y = 1.35;      // altura (Y local) donde arranca la sombra
uniform float _softness: hint_range(0.001, 0.3) = 0.04;   // ancho del degradado del corte
uniform float _fresnel_power: hint_range(0.5, 8.0) = 2.0;
uniform float _fresnel_strength: hint_range(0.0, 1.0) = 0.25; // "desprendimiento" en el borde

// --- Niebla ---
uniform float _fog_scale: hint_range(1.0, 60.0) = 18.0;     // tamaño de los remolinos (más alto = humo más "picado")
uniform float _fog_speed: hint_range(0.0, 2.0) = 0.35;       // velocidad de movimiento del humo
uniform float _fog_density: hint_range(0.0, 1.0) = 0.85;     // qué tan denso/opaco es (1 = casi nunca deja ver nada)
uniform float _fog_contrast: hint_range(0.5, 4.0) = 1.8;     // qué tan marcados quedan los remolinos vs. una niebla pareja

varying float mask;
varying vec3 world_pos;

void vertex() {
	mask = smoothstep(_threshold_y - _softness, _threshold_y + _softness, VERTEX.y);
	world_pos = VERTEX;
}

// Ruido de valor 2D barato (hash + interpolación suave), sin necesitar
// texturas extra: alcanza para un efecto de humo convincente a este tamaño.
float _hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float _value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = _hash(i);
	float b = _hash(i + vec2(1.0, 0.0));
	float c = _hash(i + vec2(0.0, 1.0));
	float d = _hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// fbm: varias octavas de ruido superpuestas (distinta escala/peso) para que
// el humo tenga tanto remolinos grandes como detalle fino, en vez de verse
// como una sola mancha uniforme.
float _fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += _value_noise(p) * amp;
		p *= 2.02;
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	vec4 tex = texture(_albedo_tex, UV);

	// Dos capas de humo a distinta velocidad/dirección (domain warp simple):
	// una "arrastra" a la otra, así no se ve como una textura que solo se
	// desliza en línea recta.
	vec2 base_uv = world_pos.xz * _fog_scale;
	vec2 drift_a = vec2(TIME * _fog_speed, -TIME * _fog_speed * 0.6);
	vec2 drift_b = vec2(-TIME * _fog_speed * 0.7, TIME * _fog_speed * 0.9);

	float layer_a = _fbm(base_uv + drift_a);
	float layer_b = _fbm(base_uv * 1.7 + drift_b + layer_a * 1.3);
	float smoke = mix(layer_a, layer_b, 0.6);
	smoke = clamp(pow(smoke, _fog_contrast) , 0.0, 1.0);

	// Zonas donde el humo es más "espeso" van a negro puro; el resto queda
	// entre el color de sombra y algo un poco más claro, dando variación de
	// densidad en vez de un plano parejo.
	vec3 fog_shade = mix(_shadow_color * 1.4, _fog_color, smoke * _fog_density);

	ALBEDO = mix(tex.rgb * _body_color, fog_shade, mask);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), _fresnel_power) * _fresnel_strength;
	EMISSION = fog_shade * mask * (0.3 + fres);
	ROUGHNESS = mix(ROUGHNESS, 1.0, mask);
	SPECULAR = mix(SPECULAR, 0.0, mask);
}
