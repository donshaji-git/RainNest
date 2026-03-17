/**
 * RainNest – script.js
 * Three.js Earth + Mouse Parallax + Scroll Navigation
 */

/* ────────────────────────────────────────────────────
   CONSTANTS & DOM REFS
──────────────────────────────────────────────────── */
const canvas    = document.getElementById('bg-canvas');
const loader    = document.getElementById('loading-screen');
const navDots   = document.querySelectorAll('.nav-dot');
const sections  = document.querySelectorAll('.section');
const scroller  = document.getElementById('scroll-container');
const cards     = document.querySelectorAll('.content-card');
const leftPanel = document.querySelector('.left-panel');

let currentSection = 0;

/* ────────────────────────────────────────────────────
   THREE.JS SETUP
──────────────────────────────────────────────────── */
const scene    = new THREE.Scene();
const camera   = new THREE.PerspectiveCamera(45, innerWidth / innerHeight, 0.1, 1000);
camera.position.z = 3.8;

const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
renderer.setSize(innerWidth, innerHeight);
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.1;

/* ────────────────────────────────────────────────────
   LIGHTING
──────────────────────────────────────────────────── */
// Ambient fill - very low to keep shadows deep
const ambient = new THREE.AmbientLight(0xffffff, 0.2);
scene.add(ambient);

// Sunलाइट - main source, reduced to prevent washout
const sun = new THREE.DirectionalLight(0xfaf8f0, 1.2);
sun.position.set(6, 4, 5);
scene.add(sun);

// Cyan rim light - purely for atmosphere
const rimLight = new THREE.PointLight(0x00d4ff, 5, 10);
rimLight.position.set(-5, -3, 2);
scene.add(rimLight);

// Front fill - very subtle to see the Earth texture clearly
const frontFill = new THREE.DirectionalLight(0xffffff, 0.3);
frontFill.position.set(0, 0, 8);
scene.add(frontFill);

/* ────────────────────────────────────────────────────
   EARTH — Load textures from reliable source
   Using NASA via visibleearth.nasa.gov mirror on raw jsDelivr
──────────────────────────────────────────────────── */
const textureLoader = new THREE.TextureLoader();

// Precise and Vibrant texture URLs
const EARTH_URL  = 'https://unpkg.com/three-globe/example/img/earth-blue-marble.jpg';
const CLOUD_URL  = 'https://unpkg.com/three-globe/example/img/earth-clouds.png';
const BUMP_URL   = 'https://unpkg.com/three-globe/example/img/earth-topology.png';

// Earthmesh & cloudmesh
let earthMesh, cloudMesh1, cloudMesh2;
let earthGroup = new THREE.Group();
scene.add(earthGroup);

// ── Earth ──
const earthGeo  = new THREE.SphereGeometry(1, 64, 64);
const earthMat  = new THREE.MeshStandardMaterial({
    color: 0x1a6ea8,       // fallback blue if texture fails
    roughness: 0.65,
    metalness: 0.1,
});
earthMesh = new THREE.Mesh(earthGeo, earthMat);
earthGroup.add(earthMesh);

// ── Cloud Layer 1 ──
const cloudGeo = new THREE.SphereGeometry(1.015, 64, 64);
const cloudMat = new THREE.MeshStandardMaterial({
    transparent: true,
    opacity: 0.3, // Drastically reduced to see Earth colors
    depthWrite: false,
    color: 0xffffff,
});
cloudMesh1 = new THREE.Mesh(cloudGeo, cloudMat);
earthGroup.add(cloudMesh1);

// ── Cloud Layer 2 ──
const cloudGeo2 = new THREE.SphereGeometry(1.025, 64, 64);
const cloudMat2 = new THREE.MeshStandardMaterial({
    transparent: true,
    opacity: 0.15, // Drastically reduced
    depthWrite: false,
    color: 0xffffff,
});
cloudMesh2 = new THREE.Mesh(cloudGeo2, cloudMat2);
cloudMesh2.rotation.y = Math.PI / 3;
cloudMesh2.rotation.z = 0.15;
earthGroup.add(cloudMesh2);

// ── Atmosphere glow (shader) ──
const atmoGeo = new THREE.SphereGeometry(1.15, 64, 64);
const atmoMat = new THREE.ShaderMaterial({
    transparent: true,
    side: THREE.BackSide,
    blending: THREE.AdditiveBlending,
    uniforms: {
        c:   { value: 0.4 }, /* Reduced to keep glow on the edge */
        p:   { value: 8.0 }, /* Sharper falloff */
        glowColor: { value: new THREE.Color(0x00d4ff) },
    },
    vertexShader: `
        uniform float c;
        uniform float p;
        varying float intensity;
        void main(){
            vec3 vNormal  = normalize(normalMatrix * normal);
            vec3 vNormel  = normalize(normalMatrix * vec3(0.0, 0.0, 1.0));
            float d       = max(0.0, c - dot(vNormal, vNormel));
            intensity     = pow(d, p);
            gl_Position   = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
    `,
    fragmentShader: `
        uniform vec3 glowColor;
        varying float intensity;
        void main(){
            gl_FragColor = vec4(glowColor * intensity, intensity);
        }
    `
});
const atmoMesh = new THREE.Mesh(atmoGeo, atmoMat);
earthGroup.add(atmoMesh);

// ── Load Textures (with fallback) ──
let loadedCount = 0;
const totalTextures = 3;

function onTextureLoad() {
    loadedCount++;
    if (loadedCount >= totalTextures) {
        // All done — hide loader
        hideLoader();
    }
}

function hideLoader() {
    setTimeout(() => {
        loader.classList.add('hidden');
    }, 600);
}

textureLoader.load(
    EARTH_URL,
    (tex) => {
        tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
        earthMat.map = tex;
        earthMat.color.set(0xffffff);
        earthMat.needsUpdate = true;
        onTextureLoad();
    },
    undefined,
    () => { onTextureLoad(); } // fail gracefully
);

textureLoader.load(
    CLOUD_URL,
    (tex) => {
        cloudMat.map = tex;
        cloudMat2.map = tex;
        cloudMat.needsUpdate = true;
        cloudMat2.needsUpdate = true;
        onTextureLoad();
    },
    undefined,
    () => { onTextureLoad(); }
);

textureLoader.load(
    BUMP_URL,
    (tex) => {
        earthMat.normalMap = tex;
        earthMat.normalScale.set(0.6, 0.6);
        earthMat.needsUpdate = true;
        onTextureLoad();
    },
    undefined,
    () => { onTextureLoad(); }
);

// Safety: hide loader after 5s regardless
setTimeout(hideLoader, 5000);

// ── Star Field Background ──
(function addStars() {
    const starGeo = new THREE.BufferGeometry();
    const pos = [];
    for (let i = 0; i < 3500; i++) {
        pos.push(
            (Math.random() - 0.5) * 400,
            (Math.random() - 0.5) * 400,
            (Math.random() - 0.5) * 400
        );
    }
    starGeo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    const starMat = new THREE.PointsMaterial({ color: 0xffffff, size: 0.18, transparent: true, opacity: 0.8 });
    scene.add(new THREE.Points(starGeo, starMat));
})();

/* ────────────────────────────────────────────────────
   MOUSE PARALLAX
──────────────────────────────────────────────────── */
let mouseX = 0, mouseY = 0;

document.addEventListener('mousemove', (e) => {
    mouseX = (e.clientX / innerWidth  - 0.5) * 2;  // -1 to 1
    mouseY = (e.clientY / innerHeight - 0.5) * 2;  // -1 to 1
});

/* ────────────────────────────────────────────────────
   GLOBE POSITION PER SECTION
   Moves Earth to different positions as user scrolls,
   mimicking the Hanergy-style section reveal pattern.
──────────────────────────────────────────────────── */
const earthPositions = [
    { x:  0.5, y:  0.0, z: 0 },   // 0 Home: centre-right
    { x: -0.4, y:  0.1, z: 0 },   // 1 About: slightly left
    { x:  0.6, y: -0.2, z: 0 },   // 2 How It Works: right
    { x:  0.0, y:  0.2, z: 0 },   // 3 Download: centre
    { x: -0.5, y:  0.0, z: 0 },   // 4 Contact: left
];

/* ────────────────────────────────────────────────────
   SCROLL HANDLING — snap nav + section detection
──────────────────────────────────────────────────── */
function onScroll() {
    const scrollTop = scroller.scrollTop;
    const h         = innerHeight;
    const idx       = Math.round(scrollTop / h);

    if (idx !== currentSection) {
        currentSection = idx;
        updateNav(idx);
        animateEarthToSection(idx);
        revealCard(idx);
    }
}

function updateNav(idx) {
    navDots.forEach((d, i) => d.classList.toggle('active', i === idx));
}

function revealCard(idx) {
    // Show card for active section, hide others
    cards.forEach((card, i) => {
        const section = i + 1;  // cards start from section 1
        if (idx === section) {
            card.classList.add('visible');
        } else {
            card.classList.remove('visible');
        }
    });

    // Hide left hero text when on non-home sections
    if (leftPanel) {
        if (idx === 0) {
            leftPanel.style.opacity = '1';
            leftPanel.style.transform = 'translateY(-50%)';
        } else {
            leftPanel.style.opacity = '0';
            leftPanel.style.transform = 'translateY(-50%) translateX(-40px)';
        }
    }
}

let earthTarget = { x: 0.5, y: 0 };

function animateEarthToSection(idx) {
    const pos = earthPositions[Math.min(idx, earthPositions.length - 1)];
    earthTarget.x = pos.x;
    earthTarget.y = pos.y;
}

// Nav click → scroll to section
navDots.forEach((dot, i) => {
    dot.addEventListener('click', () => {
        scroller.scrollTo({ top: i * innerHeight, behavior: 'smooth' });
    });
});

scroller.addEventListener('scroll', onScroll, { passive: true });

/* ────────────────────────────────────────────────────
   ANIMATION LOOP
──────────────────────────────────────────────────── */
const clock = new THREE.Clock();

function animate() {
    requestAnimationFrame(animate);
    const t = clock.getElapsedTime();

    // Auto-rotation
    earthMesh.rotation.y  += 0.0012;
    cloudMesh1.rotation.y += 0.0018;
    cloudMesh2.rotation.y -= 0.001;

    // Mouse parallax: gentle tilt
    const parallaxX = mouseX * 0.18;
    const parallaxY = mouseY * 0.12;
    earthGroup.rotation.y += (parallaxX - earthGroup.rotation.y) * 0.03;
    earthGroup.rotation.x += (-parallaxY - earthGroup.rotation.x) * 0.03;

    // Target position (section-based)
    earthGroup.position.x += (earthTarget.x - earthGroup.position.x) * 0.04;
    earthGroup.position.y += (earthTarget.y - earthGroup.position.y) * 0.04;

    // Gentle float
    earthGroup.position.y += Math.sin(t * 0.5) * 0.0015;

    renderer.render(scene, camera);
}

animate();

/* ────────────────────────────────────────────────────
   RESIZE
──────────────────────────────────────────────────── */
window.addEventListener('resize', () => {
    camera.aspect = innerWidth / innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(innerWidth, innerHeight);
});

/* ────────────────────────────────────────────────────
   INITIAL STATE
──────────────────────────────────────────────────── */
// Set earth to section 0 position initially
earthGroup.position.x = 0.5;
animateEarthToSection(0);
updateNav(0);
