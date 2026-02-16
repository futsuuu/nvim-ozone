local main = loadfile(vim.fn.stdpath("data") .. "/ozone/main")
if main then
    main()
else
    vim.opt.rtp:prepend(".")
    require("ozone").run()
end
require("rc")
