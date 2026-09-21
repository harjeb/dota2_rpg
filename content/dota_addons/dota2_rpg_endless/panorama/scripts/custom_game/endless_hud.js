(function () {
    "use strict";
    // Values come exclusively from the current local game's server publication.
    GameEvents.Subscribe("rpg_endless_state", function (state) {
        $("#EndlessWave").text = $.Localize("#endless_wave") + " " + state.wave;
        $("#EndlessLives").text = $.Localize("#endless_lives") + " " + state.lives + " / " + state.max_lives;
        var phase = ["setup", "prepare"].indexOf(state.phase) >= 0 ? "prepare" : state.phase === "result" ? "result" : "locked";
        $("#EndlessPhase").text = $.Localize("#endless_" + phase);
    });
})();
