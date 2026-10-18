// Stand-in for web/crowd_sim.wasm with the same C ABI as sim/crates/wasm, returning fake data.
// Used only to test the browser plumbing (glue JS + JavaScriptBridge) where the Rust wasm target is
// unavailable. Build: tools/standin/build.sh
typedef unsigned int u32;
typedef unsigned char u8;

static u8 in0[400000];
static u8 in1[4096];
static u8 out[200000];
static u32 out_len;
static u32 tick;
static int loaded;

static void put(const char *s) {
  out_len = 0;
  while (s[out_len]) { out[out_len] = (u8)s[out_len]; out_len++; }
}
static void put_num(u32 v) {
  char tmp[16]; int n = 0;
  if (v == 0) tmp[n++] = '0';
  while (v) { tmp[n++] = (char)('0' + v % 10); v /= 10; }
  while (n) out[out_len++] = (u8)tmp[--n];
}
static void put_more(const char *s) { while (*s) out[out_len++] = (u8)*s++; }

__attribute__((export_name("cc_alloc"))) u8 *cc_alloc(u32 slot, u32 len) { (void)len; return slot ? in1 : in0; }
__attribute__((export_name("cc_out_ptr"))) u8 *cc_out_ptr(void) { return out; }
__attribute__((export_name("cc_out_len"))) u32 cc_out_len(void) { return out_len; }
__attribute__((export_name("cc_load"))) int cc_load(void) { loaded = 1; tick = 0; put(""); return 0; }
__attribute__((export_name("cc_step"))) u32 cc_step(u32 n) { tick += n; return n; }
__attribute__((export_name("cc_tick"))) double cc_tick(void) { return tick; }
__attribute__((export_name("cc_is_over"))) u32 cc_is_over(void) { return 0; }
__attribute__((export_name("cc_command"))) void cc_command(void) { put("{\"ok\":true}"); }
__attribute__((export_name("cc_checksum"))) void cc_checksum(void) { put("00000000standin0"); }
__attribute__((export_name("cc_info"))) void cc_info(void) {
  put("{\"density_cols\":75,\"density_rows\":45,\"density_cell\":2.0,\"dt\":0.05,\"seed\":1,\"population\":1000,\"floats_per_agent\":16}");
}
__attribute__((export_name("cc_telemetry"))) void cc_telemetry(u32 since) {
  (void)since;
  put("{\"tick\":"); put_num(tick);
  put_more(",\"time\":"); put_num(tick / 20);
  put_more(",\"outcome\":\"running\",\"population\":{\"inside\":500,\"active\":200,\"completed\":300,\"total\":1000},"
           "\"budget\":1500,\"spent\":0,\"danger_seconds\":0,\"danger_limit\":90,\"time_limit\":900,"
           "\"gates\":[],\"areas\":[],\"signs\":[],\"barriers\":[],\"log\":[],\"heading\":{},\"fidelity\":[]}");
}
__attribute__((export_name("cc_explain"))) void cc_explain(void) { put("{}"); }
__attribute__((export_name("cc_inspect"))) void cc_inspect(float x, float y) { (void)x; (void)y; put("null"); }
__attribute__((export_name("cc_report"))) void cc_report(void) { put("{}"); }
__attribute__((export_name("cc_replay"))) void cc_replay(void) { put("{}"); }
__attribute__((export_name("cc_check_barrier"))) void cc_check_barrier(float a, float b, float c, float d) { (void)a; (void)b; (void)c; (void)d; put("{\"ok\":true}"); }
__attribute__((export_name("cc_density"))) void cc_density(void) {
  out_len = 75 * 45 * 4;
  for (u32 i = 0; i < out_len; i++) out[i] = (u8)((i % 4 == 0) ? (i / 4) % 200 : 128);
}
// 200 people in a ring around the plaza centre, moving with the tick
__attribute__((export_name("cc_render"))) void cc_render(void) {
  float *f = (float *)out;
  u32 n = 200;
  for (u32 i = 0; i < n; i++) {
    float a = (float)i * 0.0314159f + (float)tick * 0.002f;
    // cheap sin/cos (parabolic approximation) to avoid libm
    float x = a - 6.2831853f * (float)(int)(a / 6.2831853f);
    float s = x < 3.14159f ? 4 * x * (3.14159f - x) / 9.8696f : -4 * (x - 3.14159f) * (6.28318f - x) / 9.8696f;
    float xc = x + 1.5708f; xc = xc - 6.2831853f * (float)(int)(xc / 6.2831853f);
    float c = xc < 3.14159f ? 4 * xc * (3.14159f - xc) / 9.8696f : -4 * (xc - 3.14159f) * (6.28318f - xc) / 9.8696f;
    float *p = f + i * 16;
    p[0] = 0.4f; p[1] = 0; p[2] = 0; p[3] = 57.0f + 18.0f * c;
    p[4] = 0; p[5] = 0.4f; p[6] = 0; p[7] = 45.0f + 18.0f * s;
    p[8] = (float)(i % 2) / 8.0f; p[9] = (float)(i % 5) / 8.0f; p[10] = 0; p[11] = 0.2f;
    p[12] = 0; p[13] = 0; p[14] = a + 1.5708f; p[15] = (float)(i % 7) / 7.0f;
  }
  out_len = n * 16 * 4;
}
