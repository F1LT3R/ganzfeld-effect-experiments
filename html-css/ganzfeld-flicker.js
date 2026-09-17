// Ganzfeld Flicker Simulator - CSS Background Version
// Uses AudioContext timing with CSS background updates for maximum precision
// Drag left/right to change frequency (min 1 Hz, max 40 Hz)
// Drag up/down to change modulation depth (min 0, max 255)

// Create overlay div for UI
const overlay = document.createElement('div');
overlay.id = 'ganzflicker-overlay';
overlay.style.position = 'fixed';
overlay.style.top = '0';
overlay.style.left = '0';
overlay.style.width = '100vw';
overlay.style.height = '100vh';
overlay.style.zIndex = '999998';
overlay.style.pointerEvents = 'none';
overlay.style.fontFamily = 'monospace';
overlay.style.fontSize = '14px';
overlay.style.color = 'rgba(255, 255, 255, 0.7)';
overlay.style.padding = '20px';
overlay.style.boxSizing = 'border-box';
// document.body.appendChild(overlay);

// Create flicker background element
const flickerBg = document.createElement('div');
flickerBg.id = 'ganzflicker-bg';
flickerBg.style.position = 'fixed';
flickerBg.style.top = '0';
flickerBg.style.left = '0';
flickerBg.style.width = '100vw';
flickerBg.style.height = '100vh';
flickerBg.style.zIndex = '999997';
flickerBg.style.pointerEvents = 'none';
flickerBg.style.backgroundColor = 'rgb(0, 0, 0)';
document.body.appendChild(flickerBg);

// Create circle indicator
const circle = document.createElement('div');
circle.id = 'ganzflicker-circle';
circle.style.position = 'fixed';
circle.style.width = '80px';
circle.style.height = '80px';
circle.style.borderRadius = '50%';
circle.style.backgroundColor = 'rgba(255, 255, 255, 0.8)';
circle.style.zIndex = '999999';
circle.style.display = 'none';
circle.style.pointerEvents = 'none';
circle.style.transform = 'translate(-50%, -50%)';
circle.style.display = 'flex';
circle.style.flexDirection = 'column';
circle.style.justifyContent = 'center';
circle.style.alignItems = 'center';
circle.style.fontSize = '12px';
circle.style.fontWeight = 'bold';
circle.style.color = 'rgb(0, 0, 0)';
circle.style.fontFamily = 'monospace';
circle.style.lineHeight = '1.2';
document.body.appendChild(circle);

let eKeyDown, eClick, initialized

const init = () => {
	if (initialized) {
		return
	}
	
	console.log('init')
	// Initialize AudioContext for precision timing
	const audioCtx = new (window.AudioContext || window.webkitAudioContext)();

	// State
	let frequency = 10; // Hz
	let modulationDepth = 255; // 0-255
	let isMouseDown = false;
	let startX = 0;
	let startY = 0;
	let startFrequency = 7.5;
	let startModulation = 255;
	let mouseX = 0;
	let mouseY = 0;
	let isAnimating = true;
	let animationFrameId = null;
	let audioStartTime = audioCtx.currentTime;
	let isRed = false; // Current color state

	// Mouse tracking
	document.addEventListener('mousedown', (e) => {
		isMouseDown = true;
		startX = e.clientX;
		startY = e.clientY;
		startFrequency = frequency;
		startModulation = modulationDepth;
		circle.style.display = 'flex';
	});

	document.addEventListener('mouseup', () => {
		isMouseDown = false;
		circle.style.display = 'none';
	});

	document.addEventListener('mousemove', (e) => {
		mouseX = e.clientX;
		mouseY = e.clientY;

		if (!isMouseDown) return;

		// Horizontal drag: frequency (1-50 Hz)
		const deltaX = e.clientX - startX;
		const pixelsPerHz = window.innerWidth / 49;
		frequency = Math.max(
			1,
			Math.min(50, startFrequency + deltaX / pixelsPerHz)
		);

		// Vertical drag controls modulation depth (0-255)
		const deltaY = e.clientY - startY;
		const modulationRange = 255;
		const pixelsPerModulation = window.innerHeight / modulationRange;
		modulationDepth = Math.max(0, Math.min(255, startModulation - (deltaY / pixelsPerModulation)));

		// Update circle position and text
		updateCircle();
	});

	function updateCircle() {
		circle.style.left = mouseX + 'px';
		circle.style.top = mouseY + 'px';
		circle.innerHTML = `
			<div>${frequency.toFixed(1)}Hz</div>
			<div>${modulationDepth.toFixed(0)}</div>
		`;
	}

	function updateOverlay() {
		let text = `Frequency: ${frequency.toFixed(2)} Hz<br>`;
		text += `Modulation: ${modulationDepth.toFixed(0)} / 255<br>`;

		if (isAnimating) {
			text += `Drag left/right for frequency | Drag up/down for modulation<br>`;
			text += `Space to pause | ESC to close`;
		} else {
			text += `[PAUSED]<br>`;
			text += `Space to resume | ESC to close`;
		}

		overlay.innerHTML = text;
		}

		// Animation loop - update flicker color based on AudioContext timing
		function animate() {
		if (isAnimating) {
			// Use AudioContext.currentTime for ultra-precise timing
			const elapsedTime = audioCtx.currentTime - audioStartTime;
			const period = 1 / frequency;
			const phase = elapsedTime % period;
			const halfPeriod = period / 2;
			
			// Determine if we should be red or black
			const shouldBeRed = phase < halfPeriod;
			if (shouldBeRed) {
			// Red with modulation depth
			const alpha = modulationDepth / 255;
			flickerBg.style.backgroundColor = `rgba(255, 0, 0, ${alpha})`;
			} else {
			// Black
			flickerBg.style.backgroundColor = 'rgb(0, 0, 0)';
			}
		} else {
			// Paused - show black
			flickerBg.style.backgroundColor = 'rgb(0, 0, 0)';
		}

		updateOverlay();
			animationFrameId = requestAnimationFrame(animate);
		}

		// Start animation
		animationFrameId = requestAnimationFrame(animate);

		// Keyboard controls
		document.addEventListener('keydown', (e) => {
		if (e.key === ' ') {
			e.preventDefault();
			isAnimating = !isAnimating;
			if (isAnimating) {
			audioStartTime = audioCtx.currentTime;
			}
			console.log(isAnimating ? 'Resumed' : 'Paused');
		} else if (e.key === 'Escape') {
			flickerBg.remove();
			overlay.remove();
			circle.remove();
			cancelAnimationFrame(animationFrameId);
			audioCtx.close();
			console.log('Ganzflicker stopped');
		}
	});

	console.log('Ganzflicker CSS active!');
	console.log('Drag left/right to change frequency (1-40 Hz)');
	console.log('Drag up/down to change modulation depth (0-255)');
	console.log('Space to pause | ESC to close');

	if (!initialized) {
		document.removeEventListener(eKeyDown, init) 
		document.removeEventListener(eClick, init)
		initialized = true
	}
}

eKeyDown = document.addEventListener('keydown', init)
eClick = document.addEventListener('mousedown', init)
