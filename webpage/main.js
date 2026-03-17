import * as THREE from 'three';

// 1. Scene Setup
const canvas = document.querySelector('#bg-canvas');
const scene = new THREE.Scene();
const camera = new THREE.Camera(); // Temporary, replaced below

const renderer = new THREE.WebGLRenderer({
    canvas: canvas,
    antialias: true,
    alpha: true
});

renderer.setPixelRatio(window.devicePixelRatio);
renderer.setSize(window.innerWidth, window.innerHeight);

// 2. Camera Fix
const perspectiveCamera = new THREE.PerspectiveCamera(
    75,
    window.innerWidth / window.innerHeight,
    0.1,
    1000
);
perspectiveCamera.position.z = 2.5;

// 3. Lighting
const ambientLight = new THREE.AmbientLight(0x404040, 2);
scene.add(ambientLight);

const pointLight = new THREE.PointLight(0x06b6d4, 10, 10);
pointLight.position.set(2, 2, 2);
scene.add(pointLight);

// Extra Light for Lightning
const lightningLight = new THREE.PointLight(0xffffff, 0, 50);
lightningLight.position.set(0, 2, 0);
scene.add(lightningLight);

// 4. Globe & Cloud Creation
const globeGroup = new THREE.Group();
scene.add(globeGroup);

// Load textures from a reliable CDN
const textureLoader = new THREE.TextureLoader();
const earthTexture = textureLoader.load('https://cdn.jsdelivr.net/gh/turban/earth-threejs@master/images/earth_blue_marble_2048.jpg');
const bumpMap = textureLoader.load('https://cdn.jsdelivr.net/gh/turban/earth-threejs@master/images/earth_topology_2048.jpg');

const globeGeometry = new THREE.SphereGeometry(1, 64, 64);
const globeMaterial = new THREE.MeshStandardMaterial({
    map: earthTexture,
    bumpMap: bumpMap,
    bumpScale: 0.05,
    roughness: 0.8,
    metalness: 0.2
});
const globe = new THREE.Mesh(globeGeometry, globeMaterial);
globeGroup.add(globe);

// 5. Cloud Layer
const cloudTexture = textureLoader.load('https://unpkg.com/three-globe@2.31.0/example/img/earth-clouds.png');
const cloudGeometry = new THREE.SphereGeometry(1.02, 64, 64);
const cloudMaterial = new THREE.MeshStandardMaterial({
    map: cloudTexture,
    transparent: true,
    opacity: 0.4
});
const clouds = new THREE.Mesh(cloudGeometry, cloudMaterial);
globeGroup.add(clouds);

// Atmospheric Glow Shaders (Simplified)
const glowGeometry = new THREE.SphereGeometry(1.2, 64, 64);
const glowMaterial = new THREE.ShaderMaterial({
    uniforms: {
        glowColor: { value: new THREE.Color(0x06b6d4) },
        viewVector: { value: new THREE.Vector3(0,0,1) }
    },
    vertexShader: `
        varying float intensity;
        void main() {
            vec3 vNormal = normalize( normalMatrix * normal );
            vec3 vNormel = normalize( normalMatrix * vec3(0,0,1) );
            intensity = pow( 0.7 - dot(vNormal, vNormel), 4.0 );
            gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 );
        }
    `,
    fragmentShader: `
        uniform vec3 glowColor;
        varying float intensity;
        void main() {
            vec3 glow = glowColor * intensity;
            gl_FragColor = vec4( glow, intensity );
        }
    `,
    side: THREE.BackSide,
    blending: THREE.AdditiveBlending,
    transparent: true
});
const glowMesh = new THREE.Mesh(glowGeometry, glowMaterial);
globeGroup.add(glowMesh);

// 6. Rain System (Improved Particles)
const rainCount = 2000;
const rainGeometry = new THREE.BufferGeometry();
const rainPositions = new Float32Array(rainCount * 3);
const rainVelocities = new Float32Array(rainCount);

for (let i = 0; i < rainCount * 3; i += 3) {
    rainPositions[i] = (Math.random() - 0.5) * 20;
    rainPositions[i + 1] = Math.random() * 20 - 10;
    rainPositions[i + 2] = (Math.random() - 0.5) * 20;
    rainVelocities[i/3] = 0.1 + Math.random() * 0.1;
}

rainGeometry.setAttribute('position', new THREE.BufferAttribute(rainPositions, 3));
const rainMaterial = new THREE.PointsMaterial({
    color: 0x06b6d4,
    size: 0.015,
    transparent: true,
    opacity: 0.4,
    blending: THREE.AdditiveBlending
});

const rain = new THREE.Points(rainGeometry, rainMaterial);
scene.add(rain);

// 7. Interaction and Animation
let mouseX = 0;
let mouseY = 0;
let targetX = 0;
let targetY = 0;

window.addEventListener('mousemove', (e) => {
    mouseX = (e.clientX - window.innerWidth / 2) / window.innerWidth;
    mouseY = (e.clientY - window.innerHeight / 2) / window.innerHeight;
});

function animate() {
    requestAnimationFrame(animate);

    // Rotations
    globe.rotation.y += 0.001;
    clouds.rotation.y += 0.0015;
    
    // Lerp transition for smooth movement
    targetX += (mouseX - targetX) * 0.05;
    targetY += (mouseY - targetY) * 0.05;
    
    globeGroup.rotation.y = targetX * 0.5;
    globeGroup.rotation.x = targetY * 0.2;

    // Rain Physics
    const positions = rain.geometry.attributes.position.array;
    for (let i = 0; i < positions.length; i += 3) {
        positions[i+1] -= 0.1; // gravity
        positions[i] += targetX * 0.5; // wind reactive
        
        if (positions[i+1] < -10) {
            positions[i+1] = 10;
            positions[i] = (Math.random() - 0.5) * 20;
        }
    }
    rain.geometry.attributes.position.needsUpdate = true;

    // Lightning effect
    if (Math.random() > 0.995) {
        lightningLight.intensity = 20 + Math.random() * 30;
        setTimeout(() => { lightningLight.intensity = 0; }, 50 + Math.random() * 100);
    }

    renderer.render(scene, perspectiveCamera);
}

// 9. UI Logic
document.querySelectorAll('.nav-item').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        document.querySelector(this.getAttribute('href')).scrollIntoView({
            behavior: 'smooth'
        });
    });
});

document.querySelector('#download-btn').addEventListener('click', () => {
    alert("Starting RainNest APK Download...");
    // Simulating download start
});

// 10. Resize Handling
window.addEventListener('resize', () => {
    perspectiveCamera.aspect = window.innerWidth / window.innerHeight;
    perspectiveCamera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
});

animate();
