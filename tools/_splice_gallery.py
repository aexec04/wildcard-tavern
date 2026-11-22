p = "src/Client/CollectionGallery.lua"
s = open(p).read()
a = s.index("function CollectionGallery.frameTile(")
b = s.index('-- a small brass "New" tag')
new = open("art-wip/_checks/gallery_block.lua").read()
open(p, "w").write(s[:a] + new + s[b:])
print("spliced")
