import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch

source = Path(__file__).resolve().parents[1] / "Sources/ComputeDock/Resources/collector.py"
spec = importlib.util.spec_from_file_location("collector", source)
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)

XML = """<nvidia_smi_log><gpu id="0000:01:00.0"><product_name>NVIDIA A100</product_name>
<uuid>GPU-A</uuid><fb_memory_usage><total>81920 MiB</total><used>40960 MiB</used></fb_memory_usage>
<utilization><gpu_util>98 %</gpu_util></utilization><temperature><gpu_temp>71 C</gpu_temp></temperature>
<gpu_power_readings><power_draw>245.5 W</power_draw><power_limit>400 W</power_limit></gpu_power_readings>
<processes><process_info><pid>123</pid><type>C</type><process_name>python</process_name><used_memory>2048 MiB</used_memory></process_info>
<process_info><pid>456</pid><type>G</type><process_name>Xorg</process_name><used_memory>N/A</used_memory></process_info>
<process_info><pid>123</pid><type>C</type><process_name>python</process_name><used_memory>2048 MiB</used_memory></process_info></processes></gpu>
<gpu><product_name>RTX 4090</product_name><uuid>GPU-B</uuid><utilization><gpu_util>N/A</gpu_util></utilization>
<power_readings><power_draw>50 W</power_draw></power_readings><processes/></gpu></nvidia_smi_log>"""


class CollectorTests(unittest.TestCase):
    def test_cpu_delta_excludes_guest_double_counting(self):
        first = collector.cpu_counters("cpu 100 0 50 800 50 0 0 0 70 0\n")
        second = collector.cpu_counters("cpu 160 0 70 880 90 0 0 0 110 0\n")
        self.assertEqual(first, (1000, 850))
        self.assertEqual(collector.cpu_usage(first, second), 40)
        self.assertIsNone(collector.cpu_usage(None, second))
        self.assertIsNone(collector.cpu_usage(first, first))

    def test_memory_uses_available_not_just_free(self):
        used, total = collector.memory_values("MemTotal: 8192000 kB\nMemFree: 102400 kB\nMemAvailable: 4096000 kB\n")
        self.assertEqual((used, total), (4000, 8000))

    def test_na_is_null(self):
        for text in ["N/A", "[Not Supported]", None, "-1"]:
            self.assertIsNone(collector.number(text))
        self.assertEqual(collector.number("245.5 W"), 245.5)

    def test_gpu_xml_includes_graphics_and_compute_and_deduplicates_pid(self):
        sampler = collector.Sampler()
        with patch.object(sampler, "process_details", return_value={"user": "test", "command": "python train.py", "cpuPercent": 200}):
            gpus, processes = sampler.parse_gpus(XML, 5)
        self.assertEqual(len(gpus), 2)
        self.assertEqual(gpus[0]["memoryUsed"], 40960)
        self.assertEqual(gpus[0]["powerDraw"], 245.5)
        self.assertEqual(gpus[1]["powerDraw"], 50)
        self.assertIsNone(gpus[1]["utilization"])
        self.assertEqual(len(processes), 2)
        self.assertEqual([p["type"] for p in processes], ["C", "G"])
        self.assertIsNone(processes[1]["memoryUsed"])
        self.assertEqual(processes[0]["gpuUUID"], "GPU-A")

    def test_process_stat_handles_spaces_and_parentheses(self):
        fields = ["0"] * 24
        fields[0] = "S"; fields[11] = "500"; fields[12] = "250"; fields[19] = "9999"
        self.assertEqual(collector.parse_process_stat("123 (training (worker)) " + " ".join(fields)), (750, "9999"))

    @unittest.skipUnless(Path("/proc/stat").exists(), "Live smoke test requires Linux")
    def test_live_linux_snapshot(self):
        sampler = collector.Sampler()
        snapshot = sampler.sample()
        self.assertGreater(snapshot["memoryTotal"], 0)
        self.assertGreater(snapshot["cpuCores"], 0)


if __name__ == "__main__":
    unittest.main()
