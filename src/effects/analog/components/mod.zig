const std = @import("std");

// Export common utilities
pub const common = @import("common.zig");
pub const ComponentValue = common.ComponentValue;

// Export resistor components
pub const resistor = @import("resistor.zig");
pub const Resistor = resistor.Resistor;
pub const ResistorVariants = resistor.ResistorVariants;

// Export capacitor components
pub const capacitor = @import("capacitor.zig");
pub const Capacitor = capacitor.Capacitor;
pub const CapacitorVariants = capacitor.CapacitorVariants;

// Export inductor components
pub const inductor = @import("inductor.zig");
pub const Inductor = inductor.Inductor;
pub const InductorVariants = inductor.InductorVariants;

// Export diode components
pub const diode = @import("diode.zig");
pub const DiodeParams = diode.DiodeParams;
pub const Diode = diode.Diode;
pub const DiodeModels = diode.DiodeModels;

// Export opamp components
pub const opamp = @import("opamp.zig");
pub const OpAmpParams = opamp.OpAmpParams;
pub const OpAmp = opamp.OpAmp;
pub const OpAmpModels = opamp.OpAmpModels;

// Export transistor components
pub const transistor = @import("transistor.zig");
pub const TransistorParams = transistor.TransistorParams;
pub const Transistor = transistor.Transistor;
pub const TransistorModels = transistor.TransistorModels;

// ============================================================================
// UNIT TESTS
// ============================================================================

test "resistor variants use same algorithm" {
    const carbon = ResistorVariants.carbonFilm(10000.0);
    const metal = ResistorVariants.metalFilm(10000.0);

    // Same input, same processing but different tolerances
    const input: f32 = 1.0;
    const load: f32 = 10000.0;

    const output_carbon = carbon.processSignal(input, load);
    const output_metal = metal.processSignal(input, load);

    // Same algorithm produces identical results
    try std.testing.expect(output_carbon == output_metal);
    try std.testing.expect(carbon.tolerance == 0.05);
    try std.testing.expect(metal.tolerance == 0.01);
}

test "diode models use same algorithm with different parameters" {
    const silicon = DiodeModels.diode1N4148();
    const germanium = DiodeModels.diode1N34A();

    const voltage: f32 = 0.5;

    // Different models produce different results based on parameters
    const current_si = silicon.current(voltage);
    const current_ge = germanium.current(voltage);

    try std.testing.expect(current_si != current_ge);
    try std.testing.expect(silicon.params.forward_drop > germanium.params.forward_drop);
}

test "opamp variants use same algorithm" {
    const tl072 = OpAmpModels.tl072();
    const lm358 = OpAmpModels.lm358();

    const gain_tl = tl072.gainAt(1000.0);
    const gain_lm = lm358.gainAt(1000.0);

    try std.testing.expect(gain_tl > gain_lm);
    try std.testing.expect(tl072.params.bandwidth > lm358.params.bandwidth);
}

test "capacitor variants with different dielectrics" {
    const ceramic = CapacitorVariants.ceramicNPO(1e-6);
    const film = CapacitorVariants.filmPolyester(1e-6);

    // Same capacitance, different leakage characteristics
    try std.testing.expect(ceramic.dielectric_type == .ceramic);
    try std.testing.expect(film.dielectric_type == .film);

    const leakage_ceramic = ceramic.leakageCurrent(5.0);
    const leakage_film = film.leakageCurrent(5.0);

    try std.testing.expect(leakage_ceramic > leakage_film);
}

test "transistor models parameterized" {
    const npn = TransistorModels.bc549();
    const pnp = TransistorModels.transistor2n2905();

    try std.testing.expect(npn.params.transistor_type == .npn);
    try std.testing.expect(pnp.params.transistor_type == .pnp);
    try std.testing.expect(npn.params.beta == 200.0);
    try std.testing.expect(pnp.params.beta == 100.0);
}
