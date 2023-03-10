precision highp float;

#define MAX_RANGE 1e6
//#define NUM_REFLECTIONS

//#define NUM_SPHERES
#if NUM_SPHERES != 0
uniform vec4 spheres_center_radius[NUM_SPHERES]; // ...[i] = [center_x, center_y, center_z, radius]
#endif

//#define NUM_PLANES
#if NUM_PLANES != 0
uniform vec4 planes_normal_offset[NUM_PLANES]; // ...[i] = [nx, ny, nz, d] such that dot(vec3(nx, ny, nz), point_on_plane) = d
#endif

//#define NUM_CYLINDERS
struct Cylinder {
	vec3 center;
	vec3 axis;
	float radius;
	float height;
};
#if NUM_CYLINDERS != 0
uniform Cylinder cylinders[NUM_CYLINDERS];
#endif

#define SHADING_MODE_NORMALS 1
#define SHADING_MODE_BLINN_PHONG 2
#define SHADING_MODE_PHONG 3
//#define SHADING_MODE

// materials
//#define NUM_MATERIALS
struct Material {
	vec3 color;
	float ambient;
	float diffuse;
	float specular;
	float shininess;
	float mirror;
};
uniform Material materials[NUM_MATERIALS];
#if (NUM_SPHERES != 0) || (NUM_PLANES != 0) || (NUM_CYLINDERS != 0)
uniform int object_material_id[NUM_SPHERES+NUM_PLANES+NUM_CYLINDERS];
#endif

/*
	Get the material corresponding to mat_id from the list of materials.
*/
Material get_material(int mat_id) {
	Material m = materials[0];
	for(int mi = 1; mi < NUM_MATERIALS; mi++) {
		if(mi == mat_id) {
			m = materials[mi];
		}
	}
	return m;
}

// lights
//#define NUM_LIGHTS
struct Light {
	vec3 color;
	vec3 position;
};
#if NUM_LIGHTS != 0
uniform Light lights[NUM_LIGHTS];
#endif
uniform vec3 light_color_ambient;


varying vec3 v2f_ray_origin;
varying vec3 v2f_ray_direction;

/*
	Solve the quadratic a*x^2 + b*x + c = 0. The method returns the number of solutions and store them
	in the argument solutions.
*/
int solve_quadratic(float a, float b, float c, out vec2 solutions) {

	// Linear case: bx+c = 0
	if (abs(a) < 1e-12) {
		if (abs(b) < 1e-12) {
			// no solutions
			return 0; 
		} else {
			// 1 solution: -c/b
			solutions[0] = - c / b;
			return 1;
		}
	} else {
		float delta = b * b - 4. * a * c;

		if (delta < 0.) {
			// no solutions in real numbers, sqrt(delta) produces an imaginary value
			return 0;
		} 

		// Avoid cancellation:
		// One solution doesn't suffer cancellation:
		//      a * x1 = 1 / 2 [-b - bSign * sqrt(b^2 - 4ac)]
		// "x2" can be found from the fact:
		//      a * x1 * x2 = c

		// We do not use the sign function, because it returns 0
		// float a_x1 = -0.5 * (b + sqrt(delta) * sign(b));
		float sqd = sqrt(delta);
		if (b < 0.) {
			sqd = -sqd;
		}
		float a_x1 = -0.5 * (b + sqd);


		solutions[0] = a_x1 / a;
		solutions[1] = c / a_x1;

		// 2 solutions
		return 2;
	} 
}

/*
	Check for intersection of the ray with a given sphere in the scene.
*/
bool ray_sphere_intersection(
		vec3 ray_origin, vec3 ray_direction, 
		vec3 sphere_center, float sphere_radius, 
		out float t, out vec3 normal) 
{
	vec3 oc = ray_origin - sphere_center;

	vec2 solutions; // solutions will be stored here

	int num_solutions = solve_quadratic(
		// A: t^2 * ||d||^2 = dot(ray_direction, ray_direction) but ray_direction is normalized
		1., 
		// B: t * (2d dot (o - c))
		2. * dot(ray_direction, oc),	
		// C: ||o-c||^2 - r^2				
		dot(oc, oc) - sphere_radius*sphere_radius,
		// where to store solutions
		solutions
	);

	// result = distance to collision
	// MAX_RANGE means there is no collision found
	t = MAX_RANGE+10.;
	bool collision_happened = false;

	if (num_solutions >= 1 && solutions[0] > 0.) {
		t = solutions[0];
	}
	
	if (num_solutions >= 2 && solutions[1] > 0. && solutions[1] < t) {
		t = solutions[1];
	}

	if (t < MAX_RANGE) {
		vec3 intersection_point = ray_origin + ray_direction * t;
		normal = (intersection_point - sphere_center) / sphere_radius;

		return true;
	} else {
		return false;
	}	
}

/*
	Check for intersection of the ray with a given plane in the scene.
*/
bool ray_plane_intersection(
		vec3 ray_origin, vec3 ray_direction, 
		vec3 plane_normal, float plane_offset, 
		out float t, out vec3 normal) 
{
	/** #TODO RT1.1:
	The plane is described by its normal vec3(nx, ny, nz) and an offset d.
	Point p belongs to the plane iff `dot(normal, p) = d`.

	
	- compute the ray's intersection of the plane
	- if ray and plane are parallel there is no intersection
	- otherwise compute intersection data and store it in `normal`, and `t` (distance along ray until intersection).
	- return whether there is an intersection in front of the viewer (t > 0)
	*/
	// can use the plane center if you need it
	vec3 plane_center = plane_normal * plane_offset;
	t = MAX_RANGE + 10.;

	// (o + td)n - d  =0

	if(dot(plane_normal, ray_direction) == 0.0)
		return false;
	t = (plane_offset - dot(plane_normal , ray_origin) )/ (dot(plane_normal, ray_direction)); 

	if(dot(plane_normal, ray_direction) > 0.0)
		normal = - plane_normal;
	else
		normal = plane_normal;

	//normal = ...;
	return t > 0.;
}

/*
	Check for intersection of the ray with a given cylinder in the scene.
*/
bool ray_cylinder_intersection(
		vec3 ray_origin, vec3 ray_direction, 
		Cylinder cyl,
		out float t, out vec3 normal) 
{
	/** #TODO RT1.2.2: 
	- compute the ray's first valid intersection with the cylinder
		(valid means in front of the viewer: t > 0)
	- store intersection point in `intersection_point`
	- store ray parameter in `t`
	- store normal at intersection_point in `normal`.
	- return whether there is an intersection with t > 0
	*/

	vec3 center = cyl.center;
	vec3 vec_1 = (ray_direction - dot(ray_direction, cyl.axis) * cyl.axis);
	vec3 oc = ray_origin - cyl.center;
	vec3 vec_2 = oc - dot(oc, cyl.axis) * cyl.axis;
	float a = dot(vec_1, vec_1);
	float b = 2. * dot(vec_1, vec_2);
	float c = dot(vec_2, vec_2) - cyl.radius * cyl.radius;
	vec3 intersection_point;
	t = MAX_RANGE + 10.;

	vec2 solutions;
	int num_sol = solve_quadratic(a, b, c, solutions);
	bool top_cap, bottom_cap;

	float t1, t2;

	t = solutions[0];
	if((solutions[1] > 0. && solutions[1] < t) || t < 0.)
		t = solutions[1];
	
	intersection_point = ray_origin + t * ray_direction;
	normal = normalize(intersection_point - cyl.center - dot(intersection_point - cyl.center, cyl.axis) * cyl.axis);

	float bottom_cap_dist = dot(cyl.axis, (intersection_point - (cyl.center - (cyl.axis * cyl.height / 2.))));
	float top_cap_dist = dot(cyl.axis, (intersection_point - (cyl.center + (cyl.axis * cyl.height / 2.))));
	if(bottom_cap_dist < 0.) {
		if(t == solutions[0]) 
			t = solutions[1];
		else
			t = solutions[0];
		intersection_point = ray_origin + t * ray_direction;
		normal = -normalize(intersection_point - cyl.center - dot(intersection_point - cyl.center, cyl.axis) * cyl.axis);
		bottom_cap_dist = dot(cyl.axis, (intersection_point - (cyl.center - (cyl.axis * cyl.height / 2.))));
		top_cap_dist = dot(cyl.axis, (intersection_point - (cyl.center + (cyl.axis * cyl.height / 2.))));
		if(t < 0. || bottom_cap_dist < 0.0 ||top_cap_dist > 0.0)
			return false;
	}

	if(top_cap_dist > 0.){
		if(t == solutions[0]) 
			t = solutions[1];
		else
			t = solutions[0];
		intersection_point = ray_origin + t * ray_direction;
		normal = -normalize(intersection_point - cyl.center - dot(intersection_point - cyl.center, cyl.axis) * cyl.axis);
		bottom_cap_dist = dot(cyl.axis, (intersection_point - (cyl.center - (cyl.axis * cyl.height / 2.))));
		top_cap_dist = dot(cyl.axis, (intersection_point - (cyl.center + (cyl.axis * cyl.height / 2.))));
		if(t < 0. || bottom_cap_dist < 0.0 || top_cap_dist > 0.0)
			return false;
	} 


	return t > 0.;
}


/*
	Check for intersection of the ray with any object in the scene.
*/
bool ray_intersection(
		vec3 ray_origin, vec3 ray_direction, 
		out float col_distance, out vec3 col_normal, out int material_id) 
{
	col_distance = MAX_RANGE + 10.;
	col_normal = vec3(0., 0., 0.);

	float object_distance;
	vec3 object_normal;

	// Check for intersection with each sphere
	#if NUM_SPHERES != 0 // only run if there are spheres in the scene
	for(int i = 0; i < NUM_SPHERES; i++) {
		bool b_col = ray_sphere_intersection(
			ray_origin, 
			ray_direction, 
			spheres_center_radius[i].xyz, 
			spheres_center_radius[i][3], 
			object_distance, 
			object_normal
		);

		// choose this collision if its closer than the previous one
		if (b_col && object_distance < col_distance) {
			col_distance = object_distance;
			col_normal = object_normal;
			material_id =  object_material_id[i];
		}
	}
	#endif

	// Check for intersection with each plane
	#if NUM_PLANES != 0 // only run if there are planes in the scene
	for(int i = 0; i < NUM_PLANES; i++) {
		bool b_col = ray_plane_intersection(
			ray_origin, 
			ray_direction, 
			planes_normal_offset[i].xyz, 
			planes_normal_offset[i][3], 
			object_distance, 
			object_normal
		);

		// choose this collision if its closer than the previous one
		if (b_col && object_distance < col_distance) {
			col_distance = object_distance;
			col_normal = object_normal;
			material_id =  object_material_id[NUM_SPHERES+i];
		}
	}
	#endif

	// Check for intersection with each cylinder
	#if NUM_CYLINDERS != 0 // only run if there are cylinders in the scene
	for(int i = 0; i < NUM_CYLINDERS; i++) {
		bool b_col = ray_cylinder_intersection(
			ray_origin, 
			ray_direction,
			cylinders[i], 
			object_distance, 
			object_normal
		);

		// choose this collision if its closer than the previous one
		if (b_col && object_distance < col_distance) {
			col_distance = object_distance;
			col_normal = object_normal;
			material_id =  object_material_id[NUM_SPHERES+NUM_PLANES+i];
		}
	}
	#endif

	return col_distance < MAX_RANGE;
}

/*
	Return the color at an intersection point given a light and a material, exluding the contribution
	of potential reflected rays.         
*/
vec3 lighting(
		vec3 object_point, vec3 object_normal, vec3 direction_to_camera, 
		Light light, Material mat) {

	/** #TODO RT2.1: 
	- compute the diffuse component
	- make sure that the light is located in the correct side of the object
	- compute the specular component 
	- make sure that the reflected light shines towards the camera
	- return the ouput color

	You can use existing methods for `vec3` objects such as `mirror`, `reflect`, `norm`, `dot`, and `normalize`.
	*/
	
	vec3 direction_to_light = normalize(light.position - object_point);

	if(dot(object_normal, direction_to_light) < 0.)
		return vec3(0., 0., 0.);

	vec3 diffuse = light.color * mat.diffuse * mat.color * dot(direction_to_light, object_normal);

	vec3 specular_phong, specular_blinn;
	if(SHADING_MODE == SHADING_MODE_PHONG) {
		vec3 reflection = reflect(-direction_to_light, object_normal);
		if(dot(reflection, normalize(direction_to_camera)) < 0.)
			return diffuse;

		specular_phong = light.color * mat.specular * mat.color * pow(dot(reflection, direction_to_camera), mat.shininess);

	}
	else {
		vec3 half_vector = normalize(direction_to_light + direction_to_camera);
		if(dot(normalize(object_normal), half_vector) < 0.)
			return diffuse;
		
		specular_blinn = light.color * mat.specular *  mat.color * pow(dot(object_normal, half_vector), mat.shininess);
	}
	vec3 phong_light = diffuse + specular_phong;
	vec3 blinn_light = diffuse + specular_blinn;


	/** #TODO RT2.2: 
	- shoot a shadow ray from the intersection point to the light
	- check whether it intersects an object from the scene
	- update the lighting accordingly
	*/

	vec3 shadow_ray = normalize(light.position - object_point);
	bool shadow = false;
	float col_distance;
	vec3 col_normal;
	int mat_id;

	
	shadow = ray_intersection(object_point + object_normal * 1e-3, shadow_ray, col_distance, col_normal, mat_id);
	

	vec3 intersection_point = object_point + col_distance * shadow_ray;
	if(shadow && col_distance < length(light.position - object_point) && col_distance > 1e-4)
		return vec3(0., 0., 0.);
	

	#if SHADING_MODE == SHADING_MODE_PHONG
		return phong_light;
	#endif

	#if SHADING_MODE == SHADING_MODE_BLINN_PHONG
		return blinn_light;
	#endif

	return mat.color;
}

/*
Render the light in the scene using ray-tracing!
*/
vec3 render_light(vec3 ray_origin, vec3 ray_direction) {

	/** #TODO RT2.1: 
	- check whether the ray intersects an object in the scene
	- if it does, compute the ambient contribution to the total intensity
	- compute the intensity contribution from each light in the scene and store the sum in pix_color
	*/

	
	float col_distance;
	vec3 col_normal;
	int mat_id;
	vec3 pix_color = vec3(0., 0., 0.);
		if(ray_intersection(ray_origin, ray_direction, col_distance, col_normal, mat_id)) {
			vec3 object_point = ray_origin + col_distance * ray_direction;
			Material m = get_material(mat_id); // get material of the intersected object
			vec3 direction_to_camera = -ray_direction;
			vec3 ambient = light_color_ambient * m.ambient;
			pix_color = ambient * m.color;
			for(int i = 0; i < NUM_LIGHTS; i++) {
				pix_color += lighting(object_point, col_normal, direction_to_camera, lights[i], m);
			}                 
		}
	return pix_color;

	/** #TODO RT2.3.2: 
	- create an outer loop on the number of reflections (see below for a suggested structure)
	- compute lighting with the current ray (might be reflected)
	- use the above formula for blending the current pixel color with the reflected one
	- update ray origin and direction

	We suggest you structure your code in the following way:

	vec3 pix_color          = vec3(0.);
	float reflection_weight = ...;

	for(int i_reflection = 0; i_reflection < NUM_REFLECTIONS+1; i_reflection++) {
		float col_distance;
		vec3 col_normal = vec3(0.);
		int mat_id      = 0;

		...

		Material m = get_material(mat_id); // get material of the intersected object

		ray_origin        = ...;
		ray_direction     = ...;
		reflection_weight = ...;
	}
	*/

	//vec3 pix_color = vec3(0.);

	//float col_distance;
	//vec3 col_normal = vec3(0.);
	//int mat_id = 0;
	if(ray_intersection(ray_origin, ray_direction, col_distance, col_normal, mat_id)) {
		Material m = get_material(mat_id);
		pix_color = m.color;

		#if NUM_LIGHTS != 0
		// for(int i_light = 0; i_light < NUM_LIGHTS; i_light++) {
		// // do something for each light lights[i_light]
		// }
		#endif
	}

	return pix_color;
}


/*
	Draws the normal vectors of the scene in false color.
*/
vec3 render_normals(vec3 ray_origin, vec3 ray_direction) {
	float col_distance;
	vec3 col_normal = vec3(0.);
	int mat_id = 0;

	if( ray_intersection(ray_origin, ray_direction, col_distance, col_normal, mat_id) ) {	
		return 0.5*(col_normal + 1.0);
	} else {
		vec3 background_color = vec3(0., 0., 1.);
		return background_color;
	}
}


void main() {
	vec3 ray_origin = v2f_ray_origin;
	vec3 ray_direction = normalize(v2f_ray_direction);

	vec3 pix_color = vec3(0.);

	#if SHADING_MODE == SHADING_MODE_NORMALS
	pix_color = render_normals(ray_origin, ray_direction);
	#else
	pix_color = render_light(ray_origin, ray_direction);
	#endif

	gl_FragColor = vec4(pix_color, 1.);
}
