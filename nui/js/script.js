window.addEventListener('DOMContentLoaded', () => {
    // Minigame Elements
    const minigameContainer = document.getElementById('container');
    const pinContainer = document.getElementById('pin-container');
    const attemptsSpan = document.querySelector('#attempts span');

    // Help Menu Element
    const helpMenu = document.getElementById('help-menu');

    // Minigame State
    let gameActive = false, isPushing = false, liftInterval = null;
    let attemptsLeft = 0, currentPinIndex = 0, pins = [];
    const LIFT_SPEED = 1.0, PIN_START_POS = 0, PIN_MAX_HEIGHT = 120;

    fetch(`https://${GetParentResourceName()}/nuiReady`, { method: 'POST', body: '{}' });

    window.addEventListener('message', e => {
        const data = e.data;
        if (data.action === 'startMinigame') {
            startGame(data.pins, data.attempts);
        } else if (data.action === 'playSound') {
            const sound = new Audio(`sounds/${data.sound}.ogg`);
            sound.volume = data.volume;
            sound.play();
        } else if (data.action === 'toggleHelpMenu') {
            const isVisible = helpMenu.style.display === 'block';
            helpMenu.style.display = isVisible ? 'none' : 'block';
        }
    });

    function startGame(pinCount, attemptCount) {
        attemptsLeft = attemptCount;
        currentPinIndex = 0;
        pinContainer.innerHTML = '';
        pins = [];

        for (let i = 0; i < pinCount; i++) {
            const sweetSpotSize = 15 + Math.random() * 10;
            const sweetSpotStart = 80 + Math.random() * 20;
            pins.push({ position: PIN_START_POS, isSet: false, sweetSpot: { start: sweetSpotStart, end: sweetSpotStart + sweetSpotSize } });
            const channel = document.createElement('div');
            channel.classList.add('pin-channel');
            channel.innerHTML = `<div class="sweet-spot" style="height:${sweetSpotSize}px;bottom:${sweetSpotStart}px;"></div><div class="pin"></div>`;
            pinContainer.appendChild(channel);
        }
        updateVisuals();
        minigameContainer.style.display = 'block';
        gameActive = true;
    }

    function updateVisuals() {
        if (!gameActive) return;
        attemptsSpan.textContent = attemptsLeft;
        const pinElements = document.querySelectorAll('.pin-channel');
        pinElements.forEach((channel, i) => {
            const pinData = pins[i];
            if (pinData) {
                channel.classList.toggle('active', i === currentPinIndex && !pinData.isSet);
                const pinEl = channel.querySelector('.pin');
                pinEl.classList.toggle('active', i === currentPinIndex && !pinData.isSet);
                pinEl.classList.toggle('set', pinData.isSet);
                pinEl.style.bottom = `${pinData.position}px`;
            }
        });
    }

    function handleFailure() {
        attemptsLeft--;
        updateVisuals();
        if (attemptsLeft <= 0) {
            sendResult(false);
            return;
        }
        if (pins[currentPinIndex]) {
            pins[currentPinIndex].position = PIN_START_POS;
        }
    }

    function sendResult(success) {
        if (!gameActive) return;
        gameActive = false;
        clearInterval(liftInterval); liftInterval = null;
        setTimeout(() => {
            minigameContainer.style.display = 'none';
            fetch(`https://${GetParentResourceName()}/minigameResult`, { method: 'POST', body: JSON.stringify({ success }) });
        }, 1000);
    }

    document.addEventListener('keydown', e => {
        if (!gameActive || e.key.toLowerCase() !== 'e' || liftInterval) return;
        const pin = pins[currentPinIndex];
        if (!pin || pin.isSet) return;
        liftInterval = setInterval(() => {
            pin.position += LIFT_SPEED;
            if (pin.position > PIN_MAX_HEIGHT) {
                clearInterval(liftInterval);
                liftInterval = null;
                handleFailure();
            }
            updateVisuals();
        }, 10);
    });

    document.addEventListener('keyup', e => {
        if (e.key === 'Escape' || e.key === 'Backspace') {
            if (helpMenu.style.display === 'block') {
                helpMenu.style.display = 'none';
                fetch(`https://${GetParentResourceName()}/closeHelpMenu`, { method: 'POST', body: '{}' });
            }
        }

        if (!gameActive || e.key.toLowerCase() !== 'e' || !liftInterval) return;
        clearInterval(liftInterval); liftInterval = null;
        const pin = pins[currentPinIndex];
        if (!pin) return;
        if (pin.position >= pin.sweetSpot.start && pin.position <= pin.sweetSpot.end) {
            pin.isSet = true;
            currentPinIndex++;
            if (currentPinIndex >= pins.length) {
                sendResult(true);
            }
        } else {
            handleFailure();
        }
        updateVisuals();
    });
});