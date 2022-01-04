//==============================================================================================
// Originally written in 2016 by Peter Shirley <ptrshrl@gmail.com>
//
// To the extent possible under law, the author(s) have dedicated all copyright and related and
// neighboring rights to this software to the public domain worldwide. This software is
// distributed without any warranty.
//
// You should have received a copy (see file COPYING.txt) of the CC0 Public Domain Dedication
// along with this software. If not, see <http://creativecommons.org/publicdomain/zero/1.0/>.
//==============================================================================================

#include "rtweekend.h"

#include "camera.h"
#include "color.h"
#include "hittable_list.h"
#include "material.h"
#include "sphere.h"
#include <chrono>

#include <iostream>

__device__ int foo(const ray& r, const hittable_list* world, int d) {
    hit_record* hr = new hit_record;
    if (d == 0) {
        return 0;
    }
    return foo(r, world, d - 1) + 1;
}

__device__ color ray_color(ray r, const hittable_list* world, int depth) {
    hit_record rec;
    color accu(1, 1, 1);  // accumulation of attenuation
    for (int i = depth; i > 0; i--) {
        if (world->hit(r, 0.001, infinity, &rec)) {
            ray scattered;
            color attenuation;
            if (rec.mat_ptr->scatter(r, rec, &attenuation, &scattered)) {
                accu = accu * attenuation;
                r = scattered;
                continue;
            }
            return color(0, 0, 0);
        } else {
            vec3 unit_direction = unit_vector(r.direction());
            auto t = 0.5 * (unit_direction.y() + 1.0);
            return accu * ((1.0 - t) * color(1.0, 1.0, 1.0) + t * color(0.5, 0.7, 1.0));
        }
    }

    return color(0, 0, 0);

    // hit_record rec;
    // // If we've exceeded the ray bounce limit, no more light is gathered.
    // if (depth <= 0) {
    //     return color(0, 0, 0);
    // }
    // if (world->hit(r, 0.001, infinity, &rec)) {
    //     ray scattered;
    //     color attenuation;
    //     if (rec.mat_ptr->scatter(r, rec, &attenuation, &scattered)) {
    //         if (depth == 47) {
    //             return color(0, 0, 0);
    //         }
    //         return attenuation * ray_color(scattered, world, depth - 1);
    //     }
    //     return color(0, 0, 0);
    // }

    // vec3 unit_direction = unit_vector(r.direction());
    // auto t = 0.5 * (unit_direction.y() + 1.0);
    // return (1.0 - t) * color(1.0, 1.0, 1.0) + t * color(0.5, 0.7, 1.0);
}

__global__ void random_scene(hittable_list* world) {
    world->objects = new sphere*[500];
    world->tail = 0;

    random_init();

    auto ground_material = new material(1);
    ground_material->setup1(color(0.5, 0.5, 0.5));
    world->add(new sphere(point3(0, -1000, 0), 1000, ground_material));

    for (int a = -11; a < 11; a++) {
        for (int b = -11; b < 11; b++) {
            auto choose_mat = random_double();
            point3 center(a + 0.9 * random_double(), 0.2, b + 0.9 * random_double());

            if ((center - point3(4, 0.2, 0)).length() > 0.9) {
                material* sphere_material;

                if (choose_mat < 0.8) {
                    // diffuse
                    auto albedo = color::random() * color::random();
                    sphere_material = new material(1);
                    sphere_material->setup1(albedo);
                    world->add(new sphere(center, 0.2, sphere_material));
                } else if (choose_mat < 0.95) {
                    // metal
                    auto albedo = color::random(0.5, 1);
                    auto fuzz = random_double(0, 0.5);
                    sphere_material = new material(2);
                    sphere_material->setup2(albedo, fuzz);
                    world->add(new sphere(center, 0.2, sphere_material));
                } else {
                    // glass
                    sphere_material = new material(3);
                    sphere_material->setup3(1.5);
                    world->add(new sphere(center, 0.2, sphere_material));
                }
            }
        }
    }
    auto material1 = new material(3);
    material1->setup3(1.5);
    world->add(new sphere(point3(0, 1, 0), 1.0, material1));

    auto material2 = new material(1);
    material2->setup1(color(0.4, 0.2, 0.1));
    world->add(new sphere(point3(-4, 1, 0), 1.0, material2));

    auto material3 = new material(2);
    material3->setup2(color(0.7, 0.6, 0.5), 0.0);
    world->add(new sphere(point3(4, 1, 0), 1.0, material3));
}

__global__ void ray_trace_pixel(
    camera cam, hittable_list* world, unsigned char* out_image) {

    const int image_width = 1024;
    const int image_height = 576;
    const int samples_per_pixel = 10;
    const int max_depth = 50;

    for (int k = 0; k < 4; k++) {
        int i = threadIdx.x * 4 + k, j = blockIdx.x;
        color pixel_color(0, 0, 0);
        for (int s = 0; s < samples_per_pixel; ++s) {
            auto u = (i + random_double()) / (image_width - 1);
            auto v = (j + random_double()) / (image_height - 1);
            ray r = cam.get_ray(u, v);
            // printf("%d\n", foo(r, world, 50));
            pixel_color += ray_color(r, world, max_depth);
        }

        pixel_color.postprocessing(samples_per_pixel);
        out_image[3 * (image_width * (image_height - 1 - j) + i) + 0] = pixel_color.f[2];
        out_image[3 * (image_width * (image_height - 1 - j) + i) + 1] = pixel_color.f[1];
        out_image[3 * (image_width * (image_height - 1 - j) + i) + 2] = pixel_color.f[0];
    }
}

int main(int argc, char** argv) {

    // Image
    const auto aspect_ratio = 16.0 / 9.0;
    const int image_width = 1024;
    const int image_height = 576;
    // const int samples_per_pixel = 10;
    // const int max_depth = 50;

    unsigned char* out_image = (unsigned char*)malloc(image_height * image_width * 3 * sizeof(unsigned char));
    unsigned char* dev_out_image;
    cudaMalloc(&dev_out_image, image_height * image_width * 3 * sizeof(unsigned char));

    hittable_list* world;
    cudaMalloc(&world, sizeof(hittable_list));
    random_scene<<<1, 1>>>(world);
    cudaDeviceSynchronize();

    // Camera

    point3 lookfrom(13, 2, 3);
    point3 lookat(0, 0, 0);
    vec3 vup(0, 1, 0);
    auto dist_to_focus = 10.0;
    auto aperture = 0.1;

    camera cam(lookfrom, lookat, vup, 20, aspect_ratio, aperture, dist_to_focus);

    // Render
    // std::chrono::duration<double> t;
    // auto startTime = std::chrono::steady_clock::now(), endTime = startTime;

    ray_trace_pixel<<<image_height, 256>>>(cam, world, dev_out_image);
    cudaDeviceSynchronize();

    // endTime = std::chrono::steady_clock::now();
    // t = endTime - startTime;
    // std::cout << t.count() << "secs." << std::endl;

    cudaMemcpy(out_image, dev_out_image, image_height * image_width * 3 * sizeof(unsigned char),
               cudaMemcpyDeviceToHost);

    write_png(argv[1], out_image, image_height, image_width, 3);
    std::cerr << "\nDone.\n";
}
